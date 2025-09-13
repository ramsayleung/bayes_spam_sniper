class ProcessPendingBatchesJob < ApplicationJob
  queue_as :batching

  def perform
    BatchProcessor.process_pending_batches
  end
end
