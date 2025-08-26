class TelegramBotWorkerJob < ApplicationJob
  queue_as :bot

  def perform(token)
    Rails.logger.info "Starting bot..."
    
    current_bot = TelegramBotter.new
    current_bot.start_bot(token)
  end
end
