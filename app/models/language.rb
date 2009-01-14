class Language < SpeciesSchemaModel
  has_many :data_objects
  has_many :users
  has_many :taxon_concept_names

  named_scope :find_active, lambda { { :conditions => ['activated_on <= ?', Time.now.to_s(:db)], :order => 'sort_order ASC' } }

  @@SCIENTIFIC_ID=501 # TODO - Should not depend on this hardcoded ID for "scientific"
    
  def self.scientific
    @@scientific ||= Language.find(@@SCIENTIFIC_ID) 
  end

  def self.english # because it's a default.  No other language will have this kind of method.
    @@english ||= Language.find_by_iso_639_1('en')
  end
  
  def display_code
    iso_639_1.upcase
  end

end
# == Schema Info
# Schema version: 20081020144900
#
# Table name: languages
#
#  id           :integer(2)      not null, primary key
#  iso_639_1    :string(6)       not null
#  iso_639_2    :string(6)       not null
#  iso_639_3    :string(6)       not null
#  label        :string(100)     not null
#  name         :string(100)     not null
#  sort_order   :integer(1)      not null, default(1)
#  source_form  :string(100)     not null
#  activated_on :timestamp

