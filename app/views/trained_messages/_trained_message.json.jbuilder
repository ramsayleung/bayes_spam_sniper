json.extract! trained_message, :id, :group_id, :message, :message_type, :sender_chat_id, :created_at, :updated_at
json.url trained_message_url(trained_message, format: :json)
