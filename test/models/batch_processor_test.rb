require "test_helper"
require "minitest/mock"

class BatchProcessorTest < ActiveSupport::TestCase
  def setup
    @test_job_class = "TestJob"
    @item_data = { id: 1, message: "test message" }
    @shared_args = { group_id: 123 }

    # Mock job class for testing
    Object.const_set("TestJob", Class.new(ApplicationJob) do
      def self.perform_later(*args)
        # Mock implementation
      end
    end) unless defined?(TestJob)
  end

  def teardown
    BatchProcessor.delete_all
  end

  test "add_to_batch should add item to existing batch" do
    batch_key_for_test = "test_batch_key_#{SecureRandom.hex(16)}"
    existing_batch = BatchProcessor.create!(
      batch_key: batch_key_for_test,
      job_class: @test_job_class,
      shared_args: {},
      pending_items: [ { id: 999 } ],
      pending_count: 1,
      batch_size: 100,
      batch_window_in_seconds: 30
    )

    assert_no_difference "BatchProcessor.count" do
      BatchProcessor.add_to_batch(batch_key_for_test, @test_job_class, @item_data)
    end

    existing_batch.reload
    expected_items = [
      { "id" => 999 },
      @item_data.stringify_keys
    ]
    assert_equal expected_items, existing_batch.pending_items
    assert_equal 2, existing_batch.pending_count
  end

  test "add_to_batch should call process_batch when should_process_batch returns true" do
    batch_key = "test_batch_key_#{SecureRandom.hex(16)}"
    BatchProcessor.stub :process_batch, ->(batch) { @processed_batch = batch } do
      BatchProcessor.add_to_batch(batch_key, @test_job_class, @item_data, batch_size: 1, batch_window: 1)

      assert_not_nil @processed_batch
      assert_equal batch_key, @processed_batch.batch_key
    end
  end

  # should_process_batch? tests
  test "should_process_batch should return true when batch is full" do
    batch = BatchProcessor.new(
      batch_key: "this is a batch key_#{SecureRandom.hex(16)}",
      batch_size: 3,
      pending_count: 3
    )
    assert BatchProcessor.send(:should_process_batch?, batch)
  end

  test "should_process_batch should return true when batch window has expired" do
    batch = BatchProcessor.new(
      batch_key: "this is a batch key_#{SecureRandom.hex(16)}",
      batch_size: 3,
      pending_count: 1,
      batch_window_in_seconds: 30,
      last_processed_at: 31.seconds.ago
    )
    assert BatchProcessor.send(:should_process_batch?, batch)
  end

  test "should_process_batch should return false when batch is not full and window has not expired" do
    batch = BatchProcessor.new(
      batch_key: "this is a batch key_#{SecureRandom.hex(16)}",
      batch_size: 3,
      pending_count: 1,
      batch_window_in_seconds: 30,
      last_processed_at: 10.seconds.ago
    )
    assert_not BatchProcessor.send(:should_process_batch?, batch)
  end

  # process_batch tests
  test "process_batch should enqueue job with pending items and shared args" do
    batch = BatchProcessor.create!(
      batch_key: "batch_key_#{SecureRandom.hex(16)}",
      job_class: @test_job_class,
      shared_args: @shared_args,
      pending_items: [ @item_data, { id: 2, message: "another message" } ],
      pending_count: 2
    )

    job_performed = false
    TestJob.stub :perform_later, ->(items, **args) {
      job_performed = true
      assert_equal batch.pending_items, items
      assert_equal({ group_id: 123 }, args)
    } do
      BatchProcessor.send(:process_batch, batch)
    end

    assert job_performed, "TestJob.perform_later should have been called"
  end

  test "process_batch should clear pending items and count after processing" do
    batch = BatchProcessor.create!(
      batch_key: "batch_key_#{SecureRandom.hex(16)}",
      job_class: @test_job_class,
      shared_args: @shared_args,
      pending_items: [ @item_data, { id: 2, message: "another message" } ],
      pending_count: 2
    )

    TestJob.stub :perform_later, ->(*args) { } do
      BatchProcessor.send(:process_batch, batch)
    end

    batch.reload
    assert_equal [], batch.pending_items
    assert_equal 0, batch.pending_count
  end

  test "process_batch should not enqueue job when pending_items is blank" do
    empty_batch = BatchProcessor.create!(
      batch_key: "batch_key_#{SecureRandom.hex(16)}",
      job_class: @test_job_class,
      pending_items: [],
      pending_count: 0
    )

    job_called = false
    TestJob.stub :perform_later, ->(*args) { job_called = true } do
      BatchProcessor.send(:process_batch, empty_batch)
    end

    assert_not job_called, "TestJob.perform_later should not have been called"
  end

  # process_pending_batches tests
  test "process_pending_batches should process only expired batches with pending items" do
    recent_batch = BatchProcessor.create!(
      batch_key: "recent_batch_#{SecureRandom.hex(16)}",
      job_class: @test_job_class,
      pending_count: 5,
      batch_window_in_seconds: 30,
      last_processed_at: 10.seconds.ago
    )

    old_batch = BatchProcessor.create!(
      batch_key: "old_batch_#{SecureRandom.hex(16)}",
      job_class: @test_job_class,
      pending_count: 2,
      batch_window_in_seconds: 30,
      last_processed_at: 35.seconds.ago
    )

    empty_batch = BatchProcessor.create!(
      batch_key: "empty_batch_#{SecureRandom.hex(16)}",
      job_class: @test_job_class,
      pending_count: 0,
      batch_window_in_seconds: 30,
      last_processed_at: 35.seconds.ago
    )

    processed_batches = []
    BatchProcessor.stub :process_batch, ->(batch) { processed_batches << batch } do
      BatchProcessor.process_pending_batches
    end

    assert_includes processed_batches, old_batch
    assert_not_includes processed_batches, recent_batch
    assert_not_includes processed_batches, empty_batch
  end
end
