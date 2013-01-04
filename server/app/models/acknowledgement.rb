class Acknowledgement < ActiveRecord::Base
  attr_accessible :acknowledged_at, :acknowledged_until, :client_id, :user, :note
  belongs_to :client, :inverse_of => :acknowledgements

  validates :client, presence: true
  
end
