FactoryGirl.define do
  factory :level do
    name 'SI-A-00-00'
    longname 'the basics'
    completed false
    scores []

    after(:create) do |level, evaluator|
      create_list(:score, 20, level: level) if level.scores.nil?
    end
  end
end
