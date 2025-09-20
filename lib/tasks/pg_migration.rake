namespace :pg_migration do
  desc "Export all data to JSON for PostgreSQL migration"
  task export_data: :environment do
    data = {}

    # Export all models
    [ TrainedMessage, BannedUser, GroupClassifierState ].each do |model|
      puts "Exporting #{model.name}..."
      data[model.table_name] = model.all.as_json
    end

    filepath = Rails.root.join("db", "data", "pg_migration_data.json")
    FileUtils.mkdir_p(File.dirname(filepath))

    File.write(filepath, JSON.pretty_generate(data))
    puts "Data exported to #{filepath}"
    puts "Records: #{data.values.sum(&:length)}"
  end

  desc "Import data from JSON after PostgreSQL migration"
  task import_data: :environment do
    filepath = Rails.root.join("db", "data", "pg_migration_data.json")

    unless File.exist?(filepath)
      puts "ERROR: Migration file not found at #{filepath}"
      next
    end

    data = JSON.parse(File.read(filepath))
    now = Time.current # Use the same timestamp for all imported records

    # Import in dependency order
    if data["trained_messages"]
      puts "Importing #{data["trained_messages"].length} TrainedMessage records..."

      # Prepare the data for bulk insert
      attributes = data["trained_messages"].map do |record|
        record.delete("id")
        # Add timestamps if they don't exist in your JSON data
        record["created_at"] ||= now
        record["updated_at"] ||= now
        record
      end

      # Perform the bulk insert
      TrainedMessage.insert_all!(attributes)
    end

    # Repeat for BannedUser
    if data["banned_users"]
      puts "Importing #{data["banned_users"].length} BannedUser records..."
      attributes = data["banned_users"].map do |record|
        record.delete("id")
        record["created_at"] ||= now
        record["updated_at"] ||= now
        record
      end
      BannedUser.insert_all!(attributes)
    end

    # Repeat for GroupClassifierState
    if data["group_classifier_states"]
      puts "Importing #{data["group_classifier_states"].length} GroupClassifierStates records..."
      attributes = data["group_classifier_states"].map do |record|
        record.delete("id")
        record["created_at"] ||= now
        record["updated_at"] ||= now
        record
      end
      GroupClassifierState.insert_all!(attributes)
    end

    puts "Migration complete!"
  end
end
