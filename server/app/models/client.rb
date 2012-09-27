class Client < ActiveRecord::Base
  extend FriendlyId
  friendly_id :name, use: :slugged
  
  attr_accessible :name, :idleness, :metrics_attributes,
    :updated_at, :acknowledged_at, :acknowledged_until
  
  has_many :metrics, :dependent => :destroy
  
  accepts_nested_attributes_for :metrics, :allow_destroy => true
  
  validates :name, presence: true, uniqueness: true
  # Idleness is a percentage
  validates :idleness,
    numericality: {
      only_integer: true,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 100,
      allow_nil: true }
end
