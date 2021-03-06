class Collection < ActiveRecord::Base

  include EOL::ActivityLoggable

  belongs_to :user
  belongs_to :community # These are focus lists
  belongs_to :sort_style

  has_many :collection_items
  accepts_nested_attributes_for :collection_items
  has_many :others_collection_items, :class_name => CollectionItem.to_s, :as => :object
  has_many :containing_collections, :through => :others_collection_items, :source => :collection

  has_many :comments, :as => :parent
  # NOTE - You MUST use single-quotes here, lest the #{id} be interpolated at compile time. USE SINGLE QUOTES.
  # this will return the communities which have collected this collection. Those communities 'feature' this collection
  has_many :communities,
    :finder_sql => 'SELECT cm.* FROM communities cm, collections c, collection_items ci ' +
      'WHERE ci.object_type = "Collection" AND ci.object_id = #{id} ' +
      'AND ci.collection_id = c.id AND c.community_id = cm.id AND cm.published = 1'

  has_one :resource
  has_one :resource_preview, :class_name => Resource.to_s, :foreign_key => :preview_collection_id

  named_scope :focus, :conditions => 'community_id IS NOT NULL'
  named_scope :nonfocus, :conditions => 'community_id IS NULL'

  validates_presence_of :name

  validates_uniqueness_of :name, :scope => [:user_id]
  validates_uniqueness_of :community_id, :if => Proc.new {|l| ! l.community_id.blank? }

  before_update :set_relevance_if_collection_items_changed

  has_attached_file :logo,
    :path => $LOGO_UPLOAD_DIRECTORY,
    :url => $LOGO_UPLOAD_PATH,
    :default_url => "/images/blank.gif"

  validates_attachment_content_type :logo,
    :content_type => ['image/pjpeg','image/jpeg','image/png','image/gif', 'image/x-png']
  validates_attachment_size :logo, :in => 0..$LOGO_UPLOAD_MAX_SIZE

  index_with_solr :keywords => [ :name ], :fulltexts => [ :description ]

  define_core_relationships :select => '*'

  alias :items :collection_items
  alias_attribute :summary_name, :name

  def self.which_contain(what)
    Collection.find(:all, :joins => :collection_items, :conditions => "collection_items.object_type='#{what.class.name}' and collection_items.object_id=#{what.id}").uniq
  end

  # this method will quickly get the counts for multiple collections at the same time
  def self.add_counts(collections)
    collection_ids = collections.map(&:id).join(',')
    return if collection_ids.empty?
    collections_with_counts = Collection.find_by_sql("
      SELECT c.id, count(*) as count
      FROM collections c JOIN collection_items ci ON (c.id = ci.collection_id)
      WHERE c.id IN (#{collection_ids})
      GROUP BY c.id")
    collections_with_counts.each do |cwc|
      if c = collections.detect{ |c| c.id == cwc.id }
        c['collection_items_count'] = cwc['count'].to_i
      end
    end
  end

  def self.add_taxa_counts(collections)
    collection_ids = collections.map(&:id).join(',')
    return if collection_ids.empty?
    collections_with_counts = Collection.find_by_sql("
      SELECT c.id, count(*) as count
      FROM collections c JOIN collection_items ci ON (c.id = ci.collection_id AND ci.object_type = 'TaxonConcept')
      WHERE c.id IN (#{collection_ids})
      GROUP BY c.id")
    collections_with_counts.each do |cwc|
      if c = collections.detect{ |c| c.id == cwc.id }
        c['taxa_count'] = cwc['count'].to_i
      end
    end
  end

  def special?
    special_collection_id
  end

  def editable_by?(user)
    if user_id
      return user.id == user_id # Owned by this user?
    else
      return user.member_of(community) && user.member_of(community).manager?
    end
  end

  def is_resource_collection?
    return true if resource || resource_preview
  end

  def is_focus_list?
    community_id
  end

  # NOTE - DO NOT (!) use this method in bulk... take advantage of the accepts_nested_attributes_for if you want to
  # add more than two things... because this runs an expensive calculation at the end.
  def add(what, opts = {})
    return if what.nil?
    name = "something"
    case what.class.name
    when "TaxonConcept"
      collection_items << CollectionItem.create(:object_type => "TaxonConcept", :object => what, :name => what.scientific_name, :collection => self, :added_by_user => opts[:user])
      name = what.scientific_name
    when "User"
      collection_items << CollectionItem.create(:object_type => "User", :object => what, :name => what.full_name, :collection => self, :added_by_user => opts[:user])
      name = what.username
    when "DataObject"
      collection_items << CollectionItem.create(:object_type => "DataObject", :object => what, :name => what.short_title, :collection => self, :added_by_user => opts[:user])
      name = what.data_type.simple_type('en')
    when "Community"
      collection_items << CollectionItem.create(:object_type => "Community", :object => what, :name => what.name, :collection => self, :added_by_user => opts[:user])
      name = what.name
    when "Collection"
      collection_items << CollectionItem.create(:object_type => "Collection", :object => what, :name => what.name, :collection => self, :added_by_user => opts[:user])
      name = what.name
    else
      raise EOL::Exceptions::InvalidCollectionItemType.new(I18n.t(:cannot_create_collection_item_from_class_error,
                                                                  :klass => what.class.name))
    end
    set_relevance # This is actually safe, because we don't use #add in bulk.
    what # Convenience.  Allows us to chain this command and continue using the object passed in.
  end

  def logo_url(size = 'large')
    if logo_cache_url.blank?
      return "v2/logos/collection_default.png"
    elsif size.to_s == 'small'
      DataObject.image_cache_path(logo_cache_url, '88_88')
    else
      DataObject.image_cache_path(logo_cache_url, '130_130')
    end
  end

  def taxa
    collection_items.taxa
  end

  def maintained_by
    return user if !user_id.blank?
    return community if !community_id.blank?
  end

  def has_item? item
    collection_items.any?{|ci| ci.object_type == item.class.name && ci.object_id == item.id}
  end

  def default_sort_style
    sort_style ? sort_style : SortStyle.newest
  end

  def items_from_solr(options={})
    sort_by_style = SortStyle.find(options[:sort_by].blank? ? default_sort_style : options[:sort_by])
    EOL::Solr::CollectionItems.search_with_pagination(self.id, options.merge(:sort_by => sort_by_style))
  end

  def facet_count(type)
    EOL::Solr::CollectionItems.get_facet_counts(self.id)[type]
  end

  def facet_counts
    EOL::Solr::CollectionItems.get_facet_counts(self.id)
  end

  def watch_collection?
    special? && user_id
  end

  def focus?
    community_id
  end

  def set_relevance
    update_attributes(:relevance => calculate_relevance)
  end

private

  # This should set the relevance attribute score between 0 and 100.  Use this sparringly, it's expensive to calculate:
  def calculate_relevance
    return 0 if watch_collection? # Watch collections are irrelevant.
    @taxa_count = collection_items.taxa.count
    return 0 if @taxa_count <= 0 # Collections with no taxa (ie: friend lists and the like) are irrelevant.
    # Each sub-category should return a score between 1 and 100:
    score = (calculate_feature_relevance * 0.4) + (calculate_taxa_relevance * 0.4) + (calculate_item_relevance * 0.2)
    return 0 if score <= 0
    return 100 if score >= 100
    score.to_i
  end

  def calculate_feature_relevance
    features = containing_collections.focus.count
    times_featured_score = case features
                           when 0
                             0
                           when 1..25
                             2 * features
                           else
                             50
                           end
    collected = containing_collections.nonfocus.count
    times_collected_score = case collected
                            when 0
                              0
                            when 1..30
                              collected
                            else
                              30
                            end
    is_focus_list_score = focus? ? 20 : 0
    score = times_featured_score + times_collected_score + is_focus_list_score
    return 0 if score <= 0
    return 100 if score >= 100
    return score.to_i
  end

  # Extremely focused list = high score ... too many taxa = not as relevant.
  def calculate_taxa_relevance
    taxa = @taxa_count || collection_items.taxa.count
    score = case taxa
            when 0
              0 # No taxa = irrelvant. Really, you shouldn't get here.
            when 1
              100
            when 2..4
              100 - (taxa * 4)
            when 5..300
              (80 / (taxa / 4.0)).to_i
            else
              0 # Way too big.
            end
    return 0 if score <= 0
    return 100 if score >= 100
    return score.to_i
  end

  def calculate_item_relevance
    items = collection_items.count
    annotated = collection_items.annotated.count
    item_score = case items
                 when 0..100
                   items
                 else
                   100
                 end
    percent_annotated = annotated <= 0 ? 0 : (items / annotated.to_f)
    score = ((item_score / 2) + (percent_annotated * (item_score / 2)).to_i)
    return 0 if score <= 0
    return 100 if score >= 100
    return score.to_i
  end

  def validate
    errors.add(:user_id, I18n.t(:must_be_associated_with_either_a_user_or_a_community) ) if
      self.community_id.nil? && self.user_id.nil?
    errors.add(:user_id, I18n.t(:cannot_be_associated_with_both_a_user_and_a_community) ) if
      ((! self.community_id.nil?) && (! self.user_id.nil?))
  end

  def set_relevance_if_collection_items_changed
    relevance = calculate_relevance if collection_items && collection_items.last && collection_items.last.changed?
  end

end
