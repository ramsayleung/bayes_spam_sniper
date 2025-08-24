class TelegramBotWorkerJob < ApplicationJob
  queue_as :default

  def perform(token)
    puts "Starting bot..."
    Rails.logger.info "Starting bot..."

    telegram_bot = TelegramBotter.new
    telegram_bot.start_bot(token)
  end
end
