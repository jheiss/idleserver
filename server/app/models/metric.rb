class Metric < ActiveRecord::Base
  attr_accessible :name, :idleness, :message
  
  belongs_to :client, :inverse_of => :metrics
  
  validates :client, presence: true
  validates :name, presence: true, uniqueness: { :scope => :client_id }
  # Idleness is a percentage
  validates :idleness,
    presence: true,
    numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  #validates :message, presence: true
end
