# Only run this code when the Rails server is starting.
# This prevents it from running during `assets:precompile`, `db:migrate`, etc.
if defined?(Rails::Server)
  require "telegram/bot"

  Rails.application.config.after_initialize do
    token = Rails.application.credentials.dig(:telegram_bot_token)
    TelegramBotWorkerJob.perform_later(token) if token
  end
end
