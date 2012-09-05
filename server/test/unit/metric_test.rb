require 'test_helper'

class MetricTest < ActiveSupport::TestCase
  test 'belongs to client' do
    thing = FactoryGirl.build(:metric)
    assert_instance_of Client, thing.client
  end
  test 'client must be present' do
    thing = FactoryGirl.build(:metric, client: nil)
    refute thing.valid?
    assert thing.errors[:client].any?
  end
  
  test 'name must be present' do
    thing = FactoryGirl.build(:metric, name: nil)
    refute thing.valid?
    assert thing.errors[:name].any?
  end
  test 'name must be unique within the scope of a given client' do
    c1 = FactoryGirl.create(:client)
    c2 = FactoryGirl.create(:client)
    m1 = FactoryGirl.create(:metric, name: 'unique', client: c1)
    
    m2 = FactoryGirl.build(:metric, name: 'unique', client: c1)
    refute m2.valid?
    assert m2.errors[:name].any?
    
    m3 = FactoryGirl.build(:metric, name: 'unique', client: c2)
    assert m3.valid?
  end
  
  test 'idleness must be present' do
    thing = FactoryGirl.build(:metric, idleness: nil)
    refute thing.valid?
    assert thing.errors[:idleness].any?
  end
  test 'idleness must be a percentage' do
    thing = FactoryGirl.build(:metric, idleness: -1)
    refute thing.valid?
    assert thing.errors[:idleness].any?
    
    thing = FactoryGirl.build(:metric, idleness: 'zero')
    refute thing.valid?
    assert thing.errors[:idleness].any?
    
    thing = FactoryGirl.build(:metric, idleness: 0)
    assert thing.valid?
    
    thing = FactoryGirl.build(:metric, idleness: 100)
    assert thing.valid?
  end
  
  test 'message must be present' do
    thing = FactoryGirl.build(:metric, message: nil)
    refute thing.valid?
    assert thing.errors[:message].any?
  end
end
