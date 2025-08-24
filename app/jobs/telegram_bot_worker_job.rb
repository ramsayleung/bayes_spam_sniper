class TelegramBotWorkerJob < ApplicationJob
  queue_as :default

  def perform(token, restart: false)
    if restart && @current_bot
      puts "Stopping current bot instance..."
      @current_bot.stop_bot
    end
    
    puts "Starting bot..."
    Rails.logger.info "Starting bot..."
    
    @current_bot = TelegramBotter.new
    setup_code_reloader(token) if Rails.env.development?
    @current_bot.start_bot(token)
  end

  private

  def setup_code_reloader(token)
    Thread.new do
      loop do
        sleep 1
        if Rails.application.reloader.check!
          puts "Code changed, scheduling bot restart..."
          TelegramBotWorkerJob.perform_later(token, restart: true)
          break # Exit this monitoring thread
        end
      end
    end
  end
end
