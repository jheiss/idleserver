class Metric < ActiveRecord::Base
  belongs_to :client
  
  # Validations of the client association conflict with how
  # accepts_nested_attributes_for works.  See
  # https://rails.lighthouseapp.com/projects/8994-ruby-on-rails/tickets/1943
  # If all metrics updates are done through accepts_nested_attributes_for it
  # shouldn't matter, but we don't currently enforce that.
  # This page has some good ideas of how to handle this so that the
  # validations are disabled for nested updates: 
  # http://stackoverflow.com/questions/1209200/how-to-create-nested-objects-using-accepts-nested-attributes-for
  #validates_presence_of :client_id
  #validates_associated :client
  validates_presence_of :name, :idleness
  validates_uniqueness_of :name, :scope => :client_id
  # Idleness is a percentage
  validates_inclusion_of :idleness, :in => 0..100
end
