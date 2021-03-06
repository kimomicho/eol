# Represents an entry in the Tree of Life (see Hierarchy).  This is one of the major models of the EOL codebase, and most
# data links to these instances.
class HierarchyEntry < SpeciesSchemaModel

  acts_as_tree :order => 'lft'

  belongs_to :hierarchy
  belongs_to :name
  belongs_to :rank
  belongs_to :taxon_concept
  belongs_to :vetted
  belongs_to :visibility

  has_many :agents_hierarchy_entries
  has_many :agents, :finder_sql => 'SELECT * FROM agents JOIN agents_hierarchy_entries ahe ON (agents.id = ahe.agent_id)
                                      WHERE ahe.hierarchy_entry_id = #{id} ORDER BY ahe.view_order'
  has_many :top_images
  has_many :top_unpublished_images
  has_many :synonyms
  has_many :scientific_synonyms, :class_name => Synonym.to_s,
      :conditions => 'synonyms.synonym_relation_id NOT IN (#{SynonymRelation.common_name_ids.join(",")})'
  has_many :common_names, :class_name => Synonym.to_s,
      :conditions => 'synonyms.synonym_relation_id IN (#{SynonymRelation.common_name_ids.join(",")})'
  has_many :flattened_ancestors, :class_name => HierarchyEntriesFlattened.to_s
  has_many :curator_activity_logs

  has_and_belongs_to_many :data_objects
  has_and_belongs_to_many :refs
  has_and_belongs_to_many :published_refs, :class_name => Ref.to_s, :join_table => 'hierarchy_entries_refs',
    :association_foreign_key => 'ref_id', :conditions => 'published=1 AND visibility_id=#{Visibility.visible.id}'

  has_one :hierarchies_content
  has_one :hierarchy_entry_stat

  define_core_relationships :select => {
      :hierarchy_entries => [ :id, :identifier, :hierarchy_id, :parent_id, :lft, :rgt, :taxon_concept_id, :rank_id ],
      :names => [ :string, :italicized ],
      :canonical_forms => :string,
      :hierarchies_content => [ :content_level, :image, :text, :child_image ]},
    :include => [ :name, :hierarchies_content ]

  def self.sort_by_lft(hierarchy_entries)
    hierarchy_entries.sort_by{ |he| he.lft }
  end

  def self.sort_by_name(hierarchy_entries)
    hierarchy_entries.sort_by{ |he| he.name.string.downcase }
  end

  def self.sort_by_common_name(hierarchy_entries, language)
    hierarchy_entries.sort_by{ |he| he.common_name_in_language(language).downcase }
  end

  def self.sort_by_vetted(hierarchy_entries)
    hierarchy_entries.sort_by do |he|
      vetted_view_order = he.vetted.blank? ? 0 : he.vetted.view_order
      browsable = he.hierarchy.browsable? ? 0 : 1
      [Invert(he.published),
       vetted_view_order,
       browsable,
       he.taxon_concept_id,
       he.id]
    end
  end

  def has_parent?
    self.parent_id && self.parent_id > 0
  end

  def italicized_name
    species_or_below? ? name.italicized : name.string
  end

  def canonical_form
    return name.canonical_form
  end

  def title_canonical
    return @title_canonical unless @title_canonical.nil?
    # used the ranked version first
    if name.is_surrogate?
      @title_canonical = name.string.firstcap
    elsif name.ranked_canonical_form && !name.ranked_canonical_form.string.blank?
      @title_canonical = name.ranked_canonical_form.string.firstcap
    # otherwise bare canonical form
    elsif name.canonical_form && !name.canonical_form.string.blank?
      @title_canonical = name.canonical_form.string.firstcap
    # finally just the name string
    else
      @title_canonical = name.string.firstcap
    end
  end

  def media
    {:images => hierarchies_content.image != 0 || hierarchies_content.child_image  != 0,
     :video  => hierarchies_content.flash != 0 || hierarchies_content.youtube != 0,
     :map    => hierarchies_content.map != 0}
  end

  def rank_label
    rank.nil? ? I18n.t(:taxon) : rank.label
  end

  # wrapper function used in options_from_collection_for_select
  def hierarchy_label
    hierarchy.label
  end

  # Returns true IFF this HE was included in a set of HEs because a curator added the association.  See
  # DataObject.published_entries
  def by_curated_association?
    @associated_by_curator
  end

  def associated_by_curator=(who)
    @associated_by_curator = who
  end

  def associated_by_curator
    @associated_by_curator
  end

  def species_or_below?
    return false if rank_id == 0  # this was causing a lookup for rank id=0, so I'm trying to save queries here
    return Rank.italicized_ids.include?(rank_id)
  end

  def valid
    return false if hierarchies_content.nil? # This really only happens in test environ, but...
    hierarchies_content.content_level >= $VALID_CONTENT_LEVEL
  end

  def enable
    return false if hierarchies_content.nil?
    return species_or_below? ? (hierarchies_content.text == 1 or hierarchies_content.image == 1) : valid
  end

  def ancestors(params = {}, cross_reference_hierarchy = nil)
    return @ancestors unless @ancestors.nil?
    # TODO: reimplement completing a partial hierarchy with another curated hierarchy
    add_include = []
    add_select = {}
    unless params[:include_stats].blank?
      add_include << :hierarchy_entry_stat
      add_select[:hierarchy_entry_stats] = '*'
    end
    if params[:include_common_names]
      add_include << {:taxon_concept => {:preferred_common_names => :name}}
      add_select[:taxon_concept_names] = :language_id
    end

    ancestor_ids = flattened_ancestors.collect{ |f| f.ancestor_id }
    ancestor_ids << self.id
    ancestors = HierarchyEntry.core_relationships(:add_include => add_include, :add_select => add_select).find_all_by_id(ancestor_ids)
    @ancestors = HierarchyEntry.sort_by_lft(ancestors)
  end

  def ancestors_as_string(delimiter = "|")
    ancestors.collect{ |he| he.name.string }.join(delimiter)
  end

  def children(params = {})
    add_include = []
    add_select = {}
    unless params[:include_stats].blank?
      add_include << :hierarchy_entry_stat
      add_select[:hierarchy_entry_stats] = '*'
    end
    if params[:include_common_names]
      add_include << {:taxon_concept => {:preferred_common_names => :name}}
      add_select[:taxon_concept_names] = :language_id
    end

    vis = [Visibility.visible.id, Visibility.preview.id]
    c = HierarchyEntry.core_relationships(:add_include => add_include, :add_select => add_select).find_all_by_hierarchy_id_and_parent_id_and_visibility_id(hierarchy_id, id, vis)
    if params[:include_common_names]
      return HierarchyEntry.sort_by_common_name(c, params[:common_name_language])
    else
      return HierarchyEntry.sort_by_name(c)
    end
  end

  def kingdom(hierarchy = nil)
    return ancestors(hierarchy).first rescue nil
  end

  def kingdom_entry
    entry_ancestor_ids = flattened_ancestors.collect{ |f| f.ancestor_id }
    entry_ancestor_ids << self.id
    HierarchyEntry.find_by_id_and_parent_id(entry_ancestor_ids, 0)
  end

  def smart_thumb
    return images.blank? ? nil : images.first.smart_thumb
  end

  def smart_medium_thumb
    return images.blank? ? nil : images.first.smart_medium_thumb
  end

  def smart_image
    return images.blank? ? nil : images.first.smart_image
  end

  # Some HEs have a "source database" agent, which needs to be considered in addition to normal sources.
  def source_database_agents
    @source_db_agents ||=
      agents_hierarchy_entries.select {|ar| ar.agent_role_id == AgentRole.source_database.id }.map(&:agent)
  end

  # If a HE *does* have a source database, some behavior changes (we must consider the hierarchy agent source
  # separately), so:
  def has_source_database?
    source_database_agents && ! source_database_agents.empty?
  end

  # These are all of the agents, NOT including the hierarchy agent:
  def source_agents
    agents_hierarchy_entries.select {|ar| ar.agent_role_id == AgentRole.source.id }.map(&:agent)
  end

  # This gives you the correct array of source agents that recognize the taxon.  Keep in mind that if there is a
  # source database, you MUST cite the hiearchy agent SEPARATELY, so it is not included; otherwise, it is:
  def recognized_by_agents
    if has_source_database?
      (source_database_agents + source_agents).compact
    else
      ([hierarchy.agent] + source_agents).compact
    end
  end

  # This is a full list of AgentsHierarchyEntry models associated with this HE, and should only be used when you know
  # there is no source database (the API code uses this method a lot, at the time of this writing).
  def agents_roles
    ([agent_from_hierarchy] + agents_hierarchy_entries).compact
  end

  # This is only used by #agents_roles, to add it to the list when it's actually there. Don't use this to get an Agent.
  def agent_from_hierarchy
    if h_agent = hierarchy.agent
      h_agent.full_name = hierarchy.label # To change the name from just "Catalogue of Life"
      AgentsHierarchyEntry.new(:hierarchy_entry => self, :agent => h_agent,
                               :agent_role => AgentRole.source, :view_order => 0)
    else
      nil
    end
  end

  # Walk up the list of ancestors until you find a node that we can map to the specified hierarchy.
  def find_ancestor_in_hierarchy(hierarchy)
    he = self
    until he.nil? || he.taxon_concept.nil? || he.taxon_concept.in_hierarchy?(hierarchy)
      return nil if he.parent_id == 0
      he = he.parent
    end
    return nil if he.nil? || he.taxon_concept.nil?
    he.taxon_concept.entry(hierarchy)
  end

  def vet_synonyms(options = {})
    raise "Missing :name_id"     unless options[:name_id]
    raise "Missing :language_id" unless options[:language_id]
    raise "Missing :vetted"      unless options[:vetted]
    Synonym.update_all(
      "vetted_id = #{options[:vetted].id}",
      "language_id = #{options[:language_id]} AND name_id = #{options[:name_id]} AND hierarchy_entry_id = #{id}"
    )
  end

  def outlink
    return nil if published != 1 && visibility_id != Visibility.visible.id
    this_hierarchy = hierarchy
    if !source_url.blank?
      return {:hierarchy_entry => self, :hierarchy => this_hierarchy, :outlink_url => source_url }
    elsif !this_hierarchy.outlink_uri.blank?
      # if the hierarchy outlink_uri expects an ID
      if matches = this_hierarchy.outlink_uri.match(/%%ID%%/)
        # .. and the ID exists
        unless identifier.blank?
          return {:hierarchy_entry => self, :hierarchy => this_hierarchy, :outlink_url => this_hierarchy.outlink_uri.gsub(/%%ID%%/, identifier) }
        end
      else
        # there was no %%ID%% pattern in the outlink_uri, but its not blank so its a generic URL for all entries
        return {:hierarchy_entry => self, :hierarchy => this_hierarchy, :outlink_url => this_hierarchy.outlink_uri }
      end
    end
  end

  def split_from_concept
    result = connection.execute("SELECT he2.id, he2.taxon_concept_id FROM hierarchy_entries he JOIN hierarchy_entries he2 USING (taxon_concept_id) WHERE he.id=#{self.id}").all_hashes
    unless result.empty?
      entries_in_concept = result.length
      # if there is only one member in the entry's concept there is no need to split it
      if entries_in_concept > 1
        # create a new empty concept
        new_taxon_concept = TaxonConcept.create(:published => self.published, :vetted_id => self.vetted_id, :supercedure_id => 0, :split_from => 0)

        # set the concept of this entry to the new concept
        self.taxon_concept_id = new_taxon_concept.id
        self.save!

        # update references to this entry to use new concept id
        connection.execute("UPDATE IGNORE taxon_concept_names SET taxon_concept_id=#{new_taxon_concept.id} WHERE source_hierarchy_entry_id=#{self.id}");
        connection.execute("UPDATE IGNORE hierarchy_entries he JOIN random_hierarchy_images rhi ON (he.id=rhi.hierarchy_entry_id) SET rhi.taxon_concept_id=he.taxon_concept_id WHERE he.taxon_concept_id=#{self.id}")
        return new_taxon_concept
      end
    end
    return false
  end

  def number_of_descendants
    rgt - lft - 1
  end

  def has_content?
    return false unless hierarchies_content  # this should really only happen during testing, and even that'
    hierarchies_content.content_level > 1
  end

  def is_leaf?
    return (rgt-lft == 1)
  end

  def common_name_in_language(language)
    preferred_in_language = taxon_concept.preferred_common_names.select{|tcn| tcn.language_id == language.id}
    return name.string if preferred_in_language.blank?
    preferred_in_language[0].name.string.firstcap
  end

  def preferred_classification_summary
    return '' if flattened_ancestors.blank?
    root_ancestor, immediate_parent = kingdom_and_immediate_parent
    str_to_return = root_ancestor.name.string
    str_to_return += " > " + immediate_parent.name.string if immediate_parent
    return str_to_return
  end

  def kingdom_and_immediate_parent
    return [ nil, nil ] if flattened_ancestors.blank?
    sorted_ancestors = flattened_ancestors.sort{ |a,b| a.ancestor.lft <=> b.ancestor.lft }
    root_ancestor = sorted_ancestors.first.ancestor
    immediate_parent = sorted_ancestors.pop.ancestor
    while immediate_parent && immediate_parent != root_ancestor && [ Rank.genus, Rank.species, Rank.subspecies, Rank.variety, Rank.infraspecies ].include?(immediate_parent.rank)
      immediate_parent = sorted_ancestors.pop.ancestor
    end
    immediate_parent = nil if immediate_parent == root_ancestor
    [root_ancestor, immediate_parent]
  end


end
