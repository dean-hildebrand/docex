FactoryBot.define do
  factory :organization do
    sequence(:name) { |n| "Acme #{n}" }

    trait :demo do
      demo { true }
      daily_page_cap { 50 }
    end
  end
end
