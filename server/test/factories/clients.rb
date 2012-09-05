# Read about factories at http://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :client do
    sequence(:name) {|n| "client#{n}"}
    idleness 100
  end
end
