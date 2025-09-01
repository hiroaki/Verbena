FactoryBot.define do
  factory :delivery_response do
    message_id { "MyString" }
    association :mail_queue
    responded_at { "2023-08-22 15:22:18" }
    status { "MyString" }
    contents { "MyString" }
  end
end
