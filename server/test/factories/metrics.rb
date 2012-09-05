# Read about factories at http://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :metric do
    client
    sequence(:name) {|n| "metric#{n}"}
    idleness 100
    message "Some message text"
  end
end
