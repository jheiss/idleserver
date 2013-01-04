class Client < ActiveRecord::Base
  extend FriendlyId
  friendly_id :name, use: :slugged
  
  attr_accessible :name, :idleness, :metrics_attributes,
    :updated_at, :acknowledged_at, :acknowledged_until,
    :acknowledgements_attributes, :ack_count
  
  has_many :metrics, :inverse_of => :client, :dependent => :destroy
  has_many :acknowledgements, :inverse_of => :client, :dependent => :destroy
  
  accepts_nested_attributes_for :metrics, :allow_destroy => true
  accepts_nested_attributes_for :acknowledgements, :allow_destroy => true
  
  validates :name, presence: true, uniqueness: true
  # Idleness is a percentage
  validates :idleness,
    numericality: {
      only_integer: true,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 100,
      allow_nil: true }
end
