namespace :telegram do
  require "net/http"
  desc "Set commands for the Telegram bot"
  task setup_bot: :environment do
    token = Rails.application.credentials.dig(:telegram_bot_token)

    unless token
      puts "Telegram token not found in credentials. Please run 'rails credentials:edit'."
    end

    commands = [
      { command: "start", description: "欢迎页(Welcome message)" },
      { command: "markspam", description: "删除垃圾消息并禁言(Delete the spam message and ban the sender)" },
      { command: "feedspam", description: "投喂垃圾信息来训练(Feed spam message to train the bot)" },
      { command: "listspam", description: "查看广告列表(List all spams)" },
      { command: "listbanuser", description: "查看封禁账户列表(List all banned users)" },
      { command: "setlang", description: "设置机器人语言(Set language for bot)" }
    ]
    begin
      require "telegram/bot"
      api = Telegram::Bot::Api.new(token)
      # Old command list will be overwritten
      response = api.set_my_commands(commands: commands)
      if response
        puts "Succeed to set commands"
      else
        puts "Failed to set commands: #{response['description']}"
      end

      response = api.set_chat_menu_button(
        menu_button: { type: "commands" }
      )
      if response
        puts "Succeed to set menu"
      else
        puts "Failed to set menu: #{response['description']}"
      end

      new_bio = <<~TEXT
      A machine learning-based spam detection bot that auto-block spam

      基于机器学习的广告拦截机器人，自动拦截广告, 用爱发电，代码开源: github.com/ramsayleung/bayes_spam_sniper
      TEXT

      response = api.set_my_description(description: new_bio)
      if response
        puts "Succeed to set description: #{response}"
      else
        puts "Failed to set description: #{response['description']}"
      end

      # To set profile bio, must use @BotFather /setabouttext
    rescue => e
      puts "An error occurred: #{e.message}"
    end
  end

  desc "Download Telegram photos given a list of file_ids. Usage: rake telegram:download_photos['id1,id2']"
  task :download_photos, [ :ids ] => :environment do |t, args|
    bot_token = ENV["TELEGRAM_BOT_TOKEN"] || Rails.application.credentials.dig(:telegram_bot_token)

    if args[:ids].blank?
      abort "ERROR: No IDs provided. Usage: rake telegram:download_photos['id1,id2']"
    end

    # Split by comma or space to handle lists
    all_args = [ args[:ids] ] + args.extras
    file_ids = all_args.join(" ").split(/[\s,]+/)
    download_dir = Rails.root.join("tmp", "telegram_downloads")
    FileUtils.mkdir_p(download_dir)

    puts "INFO: Starting download for #{file_ids.count} files..."

    file_ids.each_with_index do |file_id, index|
      begin
        # 3. Get File Path (API Call 1)
        uri = URI("https://api.telegram.org/bot#{bot_token}/getFile")
        uri.query = URI.encode_www_form({ file_id: file_id })

        response = Net::HTTP.get_response(uri)
        json = JSON.parse(response.body)

        unless json["ok"]
          puts "WARN: [#{index + 1}/#{file_ids.count}] Failed to resolve ID #{file_id[0..10]}...: #{json['description']}"
          next
        end

        file_path = json.dig("result", "file_path")

        # 4. Construct Download URL
        download_url = "https://api.telegram.org/file/bot#{bot_token}/#{file_path}"
        filename = File.basename(file_path)
        local_path = download_dir.join(filename)

        # 5. Download the File (API Call 2)
        File.open(local_path, "wb") do |file|
        file.write URI.open(download_url).read
      end

        puts "SUCCESS: [#{index + 1}/#{file_ids.count}] Saved: #{local_path}"

      rescue OpenURI::HTTPError => e
        puts "ERROR: [#{index + 1}/#{file_ids.count}] HTTP Error downloading #{file_id}: #{e.message}"
      rescue StandardError => e
        puts "ERROR: [#{index + 1}/#{file_ids.count}] Error processing #{file_id}: #{e.message}"
      end
    end

    puts "\nCOMPLETED. Files saved in #{download_dir}"
  end
end
