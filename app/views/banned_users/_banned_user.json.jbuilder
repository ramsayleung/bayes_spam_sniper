json.extract! banned_user, :id, :group_id, :sender_chat_id, :sender_user_name, :spam_message, :created_at, :updated_at
json.url banned_user_url(banned_user, format: :json)
