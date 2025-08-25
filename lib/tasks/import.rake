# lib/tasks/import.rake
require 'csv'

namespace :import do
  desc "Imports trained messages from a CSV file"
  task trained_messages: :environment do
    csv_file_path = Rails.root.join('data', 'training_data.csv')

    unless File.exist?(csv_file_path)
      puts "CSV file not found. Please place training_data.csv in the project root."
      next
    end

    puts "Starting CSV import..."
    
    # The CSV should have two columns: 'message' and 'type' (ham/spam)
    CSV.foreach(csv_file_path, headers: true) do |row|
      begin
        TrainedMessage.create!(
          group_id: 0, # Import to the shared classifier
          message: row['message'],
          message_type: row['type'].strip.downcase, # 'ham' or 'spam'
          sender_chat_id: 0,
          sender_user_name: "CSV Import"
        )
        print "." # Progress indicator
      rescue => e
        puts "\nFailed to import row: #{row.to_h}. Error: #{e.message}"
      end
    end

    puts "\nSuccess to import..."
  end
end
