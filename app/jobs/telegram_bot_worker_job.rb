class TelegramBotWorkerJob < ApplicationJob
  queue_as :bot

  def perform(token)
    Rails.logger.info "Starting bot..."

    # Rails is using ActiveRecord Query
    # Cache which caches the SQL query results within the same
    # request/job context, disable query caching for the entire bot worker
    ActiveRecord::Base.uncached do
      current_bot = TelegramBotter.new
      current_bot.start_bot(token)
    end
  end
end
