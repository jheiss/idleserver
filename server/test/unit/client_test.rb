require 'test_helper'

class ClientTest < ActiveSupport::TestCase
  test 'has friendly id' do
    name = 'thing'
    thing = FactoryGirl.create(:client, name: name)
    assert_equal name, thing.to_param
  end
  test 'friendly id is slugged' do
    name = 'thing thing'
    thing = FactoryGirl.create(:client, name: name)
    assert_equal 'thing-thing', thing.to_param
  end
  
  test 'has many metrics' do
    thing = FactoryGirl.create(:client)
    m1 = FactoryGirl.create(:metric, client: thing)
    m2 = FactoryGirl.create(:metric, client: thing)
    assert_equal [m1, m2], thing.metrics
  end
  test 'metrics are dependent destroy' do
    thing = FactoryGirl.create(:client)
    m1 = FactoryGirl.create(:metric, client: thing)
    m2 = FactoryGirl.create(:metric, client: thing)
    thing.destroy
    refute Metric.find_by_id(m1.id)
    refute Metric.find_by_id(m2.id)
  end
  
  test 'accepts nested attributes for metrics' do
    thing = FactoryGirl.create(:client)
    params = {
      'metrics_attributes' => [
        FactoryGirl.attributes_for(:metric),
        FactoryGirl.attributes_for(:metric),
      ]
    }
    thing.update_attributes(params)
    assert_equal 2, thing.metrics.count
  end
  test 'can destroy metrics via nested attributes' do
    thing = FactoryGirl.create(:client)
    m1 = FactoryGirl.create(:metric, client: thing)
    m2 = FactoryGirl.create(:metric, client: thing)
    params = {
      'metrics_attributes' => [
        {
          'id' => m1.id,
          '_destroy' => true,
        },
      ]
    }
    thing.update_attributes(params)
    assert_equal 1, thing.metrics.count
  end
  
  test 'name must be present' do
    thing = FactoryGirl.build(:client, name: nil)
    refute thing.valid?
    assert thing.errors[:name].any?
  end
  test 'name must be unique' do
    c1 = FactoryGirl.create(:client, name: 'unique')
    c2 = FactoryGirl.build(:client, name: 'unique')
    refute c2.valid?
    assert c2.errors[:name].any?
  end
  
  test 'idleness must be a percentage' do
    thing = FactoryGirl.build(:client, idleness: -1)
    refute thing.valid?
    assert thing.errors[:idleness].any?
    
    thing = FactoryGirl.build(:client, idleness: 'zero')
    refute thing.valid?
    assert thing.errors[:idleness].any?
    
    thing = FactoryGirl.build(:client, idleness: 0)
    assert thing.valid?
    
    thing = FactoryGirl.build(:client, idleness: 100)
    assert thing.valid?
  end
  test 'idleness can be nil' do
    thing = FactoryGirl.build(:client, idleness: nil)
    assert thing.valid?, thing.errors.full_messages.to_s
  end
end
