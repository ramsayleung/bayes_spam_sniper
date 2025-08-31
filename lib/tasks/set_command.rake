namespace :bot do
  desc "Set commands for the Telegram bot"
  task set_commands: :environment do
    token = Rails.application.credentials.dig(:telegram_bot_token)

    unless token
      puts "Telegram token not found in credentials. Please run 'rails credentials:edit'."
    end

    commands = [
      { command: "start", description: "欢迎页(Welcome message)" },
      { command: "markspam", description: "删除垃圾消息并禁言(Delete the spam message and ban the sender)" },
      { command: "feedspam", description: "投喂垃圾信息来训练(Feed spam message to train the bot)" },
      { command: "listspam", description: "查看封禁账户列表(List all banned users)" }
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
        puts "Failed to set commands: #{response['description']}"
      end
    rescue => e
      puts "An error occurred: #{e.message}"
    end
  end
end
