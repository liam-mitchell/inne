FactoryGirl.define do
  sequence(:name) { |n| "SI-A-00-#{n}" }

  factory :level do
    name
    longname 'the basics'
    completed false
    scores []

    after(:create) do |level, evaluator|
      create_list(:score, 20, level: level) if level.scores.nil?
    end
  end

  factory :episode do
    name
    completed false
    scores []

    after(:create) do |level, evaluator|
      create_list(:score, 20, level: level) if level.scores.nil?
    end
  end
end
