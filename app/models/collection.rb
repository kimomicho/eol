# A Collection represents... uhhh... a distinct collection (!) of data that a given Agent has.  For exampe, one website (one
# Agent) may have a collection of butterflie data as well as a collection of shark data. This object allows us to distinquish the
# two. This is important for citing a data object: the URI for the butterflies may be very different than the URI to sharks.
class Collection < SpeciesSchemaModel
  belongs_to :agent
  has_many   :mappings

  #TODO - Make logo associated with agents instead of a hardcoded field in the database called "logo_url" (so image can be moved to content server)
  
  # Fishbase is a collection that we reference often and have specific behaviours for, thus we want to find it simply (and cache
  # it):
  def self.fishbase
    Rails.cache.fetch(:fishbase_collection) do
      Collection.find_by_title('FishBase species detail')
    end
  end

  # Some collections want us to "ping" them every time a DataObject they authored is referenced on our site.
  def ping_host?
    return false if self[:ping_host_url].nil?
    return true
  end

  # If we are supposed to ping_host?, then we need the URL to post (including the ID of the object).
  # The code to do the actual pinging is client-side, thus there is no method for it here.
  # def ping_host_url
    # return 'http://www.fishbase.ca/utility/log/eol/record.php?id=%ID%'
  # end

end

# == Schema Info
# Schema version: 20081020144900
#
# Table name: collections
#
#  id          :integer(3)      not null, primary key
#  agent_id    :integer(4)      not null
#  description :string(300)     not null
#  link        :string(255)     not null
#  logo_url    :string(255)     not null
#  title       :string(150)     not null
#  uri         :string(255)     not null
#  vetted      :integer(1)      not null

