FactoryBot.define do
  factory :mail_queue do
    session_id { "MyString" }
    timer_at { "2023-07-03 17:41:46" }
    envelope_from { "MyString" }
    envelope_to { "MyString" }
    association :eml_source

    # 未着手
    trait :untouched do
      session_id { nil }
    end

    # 着手済
    trait :touched do
      session_id { SecureRandom.uuid }
    end
  end
end
