class TelegramBotWorkerJob < ApplicationJob
  queue_as :default

  def perform(token)
    puts "Starting bot..."
    Rails.logger.info "Starting bot..."
    
    current_bot = TelegramBotter.new
    current_bot.start_bot(token)
  end
end
