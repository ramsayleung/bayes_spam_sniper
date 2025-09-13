class BatchProcessor < ApplicationRecord
  validates :batch_key, presence: true, uniqueness: true
  validates :job_class, presence: true
  validates :pending_count, presence: true, numericality: { greater_than_or_euqal_to: 0 }

  # Generic batching configuration
  DEFAULT_BATCH_SIZE = 100
  DEFAULT_BATCH_WINDOW_IN_SECONDS = 30.seconds

  # JSON serialization for SQLite compatibility
  def shared_args
    JSON.parse(shared_args_json || "{}")
  end

  def shared_args=(value)
    self.shared_args_json = value.to_json
  end

  def pending_items
    JSON.parse(pending_items_json || "[]")
  end

  def pending_items=(value)
    self.pending_items_json = value.to_json
  end

  def self.add_to_batch(batch_key, job_class, item_data, shared_args = {}, batch_size: DEFAULT_BATCH_SIZE, batch_window: DEFAULT_BATCH_WINDOW_IN_SECONDS)
    batch = find_or_create_by(batch_key: batch_key) do |b|
      b.job_class = job_class
      b.shared_args = shared_args
      b.pending_items = []
      b.pending_count = 0
      b.batch_size = batch_size
      b.batch_window_in_seconds = batch_window.to_i
      b.last_processed_at = Time.current
    end

    current_items = batch.pending_items
    current_items << item_data
    batch.pending_items = current_items
    batch.pending_count = current_items.size
    batch.save!

    # Trigger processing ONLY if the batch is full
    if batch.pending_count >= batch.batch_size
      process_batch(batch)
    end
  end

  def self.process_pending_batches
    where("pending_count > 0")
      .find_each do |batch|
      if batch.last_processed_at < batch.batch_window_in_seconds.seconds.ago
        process_batch(batch)
      end
    end
  end

  private
  def self.should_process_batch?(batch)
    batch.pending_count >= batch.batch_size || batch.last_processed_at < batch.batch_window_in_seconds.seconds.ago
  end

  def self.process_batch(batch)
    return if batch.pending_items.blank?

    job_class = batch.job_class.constantize
    job_class.perform_later(batch.pending_items, **batch.shared_args.symbolize_keys)

    batch.update!(
      pending_items: [],
      pending_count: 0,
      last_processed_at: Time.current
    )
  end
end
