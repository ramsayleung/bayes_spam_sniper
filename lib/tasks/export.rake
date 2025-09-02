require "csv"

namespace :export do
  desc "Exports the entire TrainedMessage table to db/data/db_migration_data.csv"
  task trained_messages: :environment do
    filepath = Rails.root.join("db", "data", "db_migration_data.csv")

    puts "Starting export of TrainedMessage table to #{filepath}..."

    # Ensure the target directory exists
    FileUtils.mkdir_p(File.dirname(filepath))

    headers = TrainedMessage.column_names

    CSV.open(filepath, "w", write_headers: true, headers: headers) do |csv|
      TrainedMessage.find_each do |record|
        csv << record.attributes.values_at(*headers)
      end
    end

    puts "Successful to export #{TrainedMessage.count} records."
  end
end
