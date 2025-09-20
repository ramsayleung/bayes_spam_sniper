require "csv"

namespace :import do
  desc "Imports trained messages from db/data/trained_data.csv, will skip duplicate"
  task trained_messages: :environment do
    csv_file_path = Rails.root.join("db", "data", "trained_data.csv")

    unless File.exist?(csv_file_path)
      puts "ERROR: CSV file not found at #{csv_file_path}."
      next
    end

    puts "Starting import of #{csv_file_path}..."

    new_records = 0
    skipped_records = 0

    # A transaction ensures that if any row fails, the entire import is rolled back.
    # This prevents a partially-imported file from corrupting your data.
    ActiveRecord::Base.transaction do
      TrainedMessage.skip_callback(:create, :after, :should_ban_user)
      CSV.foreach(csv_file_path, headers: true) do |row|
        message_content = row["message"]

        # Skip rows with no message content
        next if message_content.blank?

        # This is the core of the de-duplication logic.
        # It finds a record by its unique content or initializes a new one.
        record = TrainedMessage.find_or_initialize_by(
          message: message_content,
          group_id: 0 # Using the default group_id from your script
        )

        if record.new_record?
          # These attributes are only set if a new record is being created
          record.message_type = row["type"]&.strip&.downcase || "spam"
          record.sender_chat_id = 0
          record.sender_user_name = "CSV Import"
          record.training_target = row["target"] || "message_content"

          record.save!

          print "." # New record created
          new_records += 1
        else
          print "x" # Skipped existing record
          skipped_records += 1
        end
      end
    end

    puts "\n\n Import complete!"
    puts "Imported: #{new_records} new messages."
    puts "Skipped: #{skipped_records} duplicate messages."

    rescue => e
      puts "\n\n An error occurred during the import: #{e.message}"
      puts "The transaction has been rolled back. No data was changed."
  end

  desc "Migrates all records from the db_migration_data.csv file using message_hash for uniqueness."
  task migrate_from_csv: :environment do
    require "csv"
    filepath = Rails.root.join("db", "data", "db_migration_data.csv")

    unless File.exist?(filepath)
      puts " ERROR: Migration file not found at #{filepath}."
      next
    end

    puts "Starting database migration from CSV..."

    imported_count = 0
    skipped_count = 0

    # If any record fails to import, the whole process will be rolled back.
    ActiveRecord::Base.transaction do
      TrainedMessage.skip_callback(:create, :after, :should_ban_user)
      CSV.foreach(filepath, headers: true, header_converters: :symbol) do |row|
        # 1. Calculate the message_hash from the message content in the row.
        message_text = row[:message].to_s
        message_hash = Digest::SHA256.hexdigest(message_text)

        # 2. Check for existence using the calculated message_hash.
        if TrainedMessage.exists?(message_hash: message_hash)
          skipped_count += 1
          print "x" # 'x' for skipped
        else
          # 3. Prepare the attributes, ensuring the old ID is removed
          #    and the new message_hash is included.
          attributes = row.to_h
          attributes.delete(:id) # Let the database assign a new primary key.
          attributes[:message_hash] = message_hash

          TrainedMessage.create!(attributes)
          imported_count += 1
          print "." # '.' for imported
        end
      end
    end

    puts "\n\n Migration complete!"
    puts "Imported: #{imported_count} new records."
    puts "Skipped:  #{skipped_count} existing records (based on message_hash)."
  end
end
