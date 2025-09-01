FactoryBot.define do
  factory :token do
    sequence(:label) { |n| "MyString#{n}" }
    sequence(:key) { |n| "MyString#{n}" }
  expires_at { 1.year.from_now }
  revoked_at { nil }
  last_used_at { nil }
  end
end
