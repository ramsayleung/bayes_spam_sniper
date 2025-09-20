namespace :data_migration do
  desc "Backfills the message_hash for existing TrainedMessage records that are missing it."
  task backfill_message_hashes: :environment do
    puts "Starting to backfill message_hash for TrainedMessage records..."

    # Scope to only the records that need updating to make the task runnable multiple times.
    records_to_update = TrainedMessage.where(message_hash: nil)
    total_count = records_to_update.count

    if total_count.zero?
      puts " No records to update. All trained messages already have a message_hash."
      next
    end

    puts "Found #{total_count} records to update."
    counter = 0

    # Use `find_each` to process records in memory-efficient batches (default is 1000).
    # This avoids loading the entire table into memory.
    records_to_update.find_each do |trained_message|
      # Use `to_s` to handle cases where `message` might be nil.
      hash_value = Digest::SHA256.hexdigest(trained_message.message.to_s)

      # Use `update_column` for performance. It's a direct SQL update that skips
      # validations and callbacks, which aren't needed for this backfill.
      trained_message.update_column(:message_hash, hash_value)

      counter += 1
      # Print a progress update every 1000 records to avoid spamming the console.
      if counter % 1000 == 0
        puts "Processed #{counter} of #{total_count} records..."
      end
    end

    puts "\n Successfully backfilled message_hash for #{total_count} records."
  end
  desc "Retrain all classifier"
  task retrain_all_classifier: :environment do
      SpamClassifierService.rebuild_all_public
  end
end
