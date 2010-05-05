class Client < ActiveRecord::Base
  has_many :metrics, :dependent => :destroy
  
  accepts_nested_attributes_for :metrics, :allow_destroy => true
  
  validates_presence_of :name
  validates_uniqueness_of :name
  # Idleness is a percentage
  validates_inclusion_of :idleness, :in => 0..100, :allow_nil => true
end
