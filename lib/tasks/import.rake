# lib/tasks/import.rake
require 'csv'

namespace :import do
  desc "Imports trained messages from a CSV file, skipping duplicates."
  task trained_messages: :environment do
    csv_file_path = Rails.root.join('data', 'training_data.csv')

    unless File.exist?(csv_file_path)
      puts "CSV file not found. Please place training_data.csv in the project root."
      next
    end

    puts "Starting CSV import..."
    
    new_records = 0
    skipped_records = 0

    # CSV format: 'message','type'(ham/spam)
    CSV.foreach(csv_file_path, headers: true) do |row|
      training_target = row['target'] || "message_content"
      begin
        # Find a message by its content and group_id
        record = TrainedMessage.find_or_create_by(
          message: row['message'],
          group_id: 0,
          training_target: training_target
        ) do |trained_message|
          # These attributes are only set if a new record is being created
          trained_message.message_type = row['type']&.strip&.downcase || "spam"
          trained_message.sender_chat_id = 0
          trained_message.sender_user_name = "CSV Import"
        end

        if record.previously_new_record?
          print "." # New record created
          new_records += 1
        else
          print "x" # Skipped
          skipped_records += 1
        end

      rescue => e
        puts "\nFailed to import row: #{row.to_h}. Error: #{e.message}"
      end
    end

    puts "\n\nImport complete!"
    puts "Imported: #{new_records} new messages."
    puts "Skipped: #{skipped_records} duplicate messages."
  end
end
