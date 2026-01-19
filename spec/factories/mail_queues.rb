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

    # transient 属性でステータスを外から指定できるようにします。
    transient do
      status { 'succeeded' }
    end

    # 未着手
    trait :untouched do
      session_id { nil }
      delivery_status { 'pending' }
    end

    # 着手済
    trait :touched do
      session_id { SecureRandom.uuid }
      # デフォルトは transient の `status`（:succeeded）だが、テスト側で上書き可能
      delivery_status { status }
      attempts_count { 1 }
    end
  end
end
