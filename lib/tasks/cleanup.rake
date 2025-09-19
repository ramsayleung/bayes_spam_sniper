# lib/tasks/cleanup.rake
require "csv"
require "digest"

namespace :cleanup do
  desc "Deletes records from the database based on message hashes derived from a CSV file."
  task delete_by_csv_hash: :environment do
    csv_file_path = Rails.root.join("db", "data", "need_to_clean_up.csv")

    unless File.exist?(csv_file_path)
      puts " ERROR: CSV file not found at #{csv_file_path}."
      next
    end

    puts " Starting deletion process based on #{csv_file_path}..."
    puts "This will delete records from the database."

    deleted_records_count = 0
    processed_rows_count = 0

    # A transaction ensures that if any part fails, all changes are rolled back.
    ActiveRecord::Base.transaction do
      # 1. Read the source CSV file.
      CSV.foreach(csv_file_path, headers: true) do |row|
        message_content = row["message"]
        next if message_content.blank?

        processed_rows_count += 1

        # 2. Calculate the hash for the message from the CSV.
        hash_from_csv = Digest::SHA256.hexdigest(message_content)

        # 3. Find all database records that match this hash.
        records_to_delete = TrainedMessage.where(message_hash: hash_from_csv)

        if records_to_delete.any?
          # Add the number of records we are about to delete to our counter.
          deleted_records_count += records_to_delete.count
          # 4. Delete them all.
          records_to_delete.destroy_all
          print "D" # "D" for Deleted
        else
          print "." # "." for No match found
        end
      end
    end

    puts "\n\n Cleanup complete!"
    puts "Processed: #{processed_rows_count} rows from the CSV."
    puts "Deleted: #{deleted_records_count} records from the database."

    rescue => e
      puts "\n\nAn error occurred: #{e.message}"
      puts "Transaction rolled back. No changes were made to the database."
  end
end
