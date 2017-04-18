factory :level do
  transient do
    done false
  end

  name 'SI-A-00-00'
  longname 'the basics'
  completed { done }

  after(:create) do |level, evaluator|
    create_list(:score, 20, level: level)
  end
end
