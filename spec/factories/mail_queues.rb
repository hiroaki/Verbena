FactoryBot.define do
  factory :mail_queue do
    session_id { "MyString" }
    timer_at { Time.current }
    envelope_from { "MyString" }
    envelope_to { "MyString" }
    delivery_status { 'pending' }
    attempts_count { 0 }
    locked_until { nil }
    last_attempted_at { nil }
    association :eml_source

    # 未着手
    trait :untouched do
      session_id { nil }
      delivery_status { 'pending' }
    end

    # 着手済
    trait :touched do
      session_id { SecureRandom.uuid }
      delivery_status { 'succeeded' }
    end
  end
end
