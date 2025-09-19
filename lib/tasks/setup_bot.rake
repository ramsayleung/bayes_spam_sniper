namespace :bot do
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
      { command: "listbanuser", description: "查看封禁账户列表(List all banned users)" }
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
end
