require "singleton"
require "concurrent"

class BatchScheduler
  include Singleton

  def start
    @scheduler_thread = Concurrent::TimerTask.new(execution_interval: 1.second) do
      begin
        BatchProcessor.process_pending_batches
      rescue => e
        Rails.logger.error("BatchScheduler error: #{e.message}")
      end
    end
    @scheduler_thread.execute
  end

  def stop
    @scheduler_thread&.shutdown
  end
end
