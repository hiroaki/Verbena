FactoryBot.define do
  factory :mail_queue do
    timer_at { Time.current }
    envelope_from { "MyString" }
    envelope_to { "MyString" }
    delivery_status { 'pending' }
    attempts_count { 0 }
    locked_until { nil }
    last_attempted_at { nil }
    association :eml_source
    association :token

    # Traits reflect current `delivery_status` semantics.
    # 未着手（まだジョブがキューに入っているだけ）
    trait :untouched do
      delivery_status { 'pending' }
      attempts_count { 0 }
    end

    # Claimed / processing: ジョブが実際に処理を開始した（セッションを保持）状態
    trait :claimed do
      delivery_status { 'processing' }
      attempts_count { 1 }
      last_attempted_at { Time.current }
    end

    # 互換性のためのエイリアス（古い :touched 呼び出しを置き換えられるようにする）
    trait :touched do
      delivery_status { 'succeeded' }
      attempts_count { 1 }
      last_attempted_at { Time.current }
    end

    # 結果ベースのステータスを明示的に指定するためのトレイト
    trait :succeeded do
      delivery_status { 'succeeded' }
      attempts_count { 1 }
    end

    trait :failed do
      delivery_status { 'failed' }
      attempts_count { 1 }
    end

    trait :retrying do
      delivery_status { 'retrying' }
      attempts_count { 1 }
    end
  end
end
