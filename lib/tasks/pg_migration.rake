namespace :pg_migration do
  desc "Export all data to JSON for PostgreSQL migration"
  task export_data: :environment do
    data = {}

    # Export all models
    [ TrainedMessage, BannedUser ].each do |model|
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

    ActiveRecord::Base.transaction do
      # Import in dependency order
      if data["trained_messages"]
        puts "Importinng TrainedMessage records.."
        data["trained_messages"].each do |record|
          record.delete("id")
          TrainedMessage.create!(record)
          print "."
        end
        puts "\nImported #{data["trained_messages"].length} TrainedMessage records"
      end

      if data["banned_users"]
        puts "Importing BannedUser records..."
        data["banned_users"].each do |record|
          record.delete("id")
          BannedUser.create!(record)
          print "."
        end
        puts "\nImported #{data["banned_users"].length} BannedUser records"
      end
    end
    puts "Migration complete!"
  end
end
