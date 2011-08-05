class Member < ActiveRecord::Base

  belongs_to :community
  belongs_to :user

  has_many :endorsed_collections # Collections this member has personally endorsed for the community

  has_and_belongs_to_many :roles

  validates_uniqueness_of :user_id, :scope => :community_id

  # You should be able to call manager? to test whether the member is ... uhhh... a manager.

end
