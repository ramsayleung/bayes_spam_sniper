namespace :bot do
  desc "Set commands for the Telegram bot"
  task set_commands: :environment do
    token = Rails.application.credentials.dig(:telegram_bot_token)

    unless token
      puts "Telegram token not found in credentials. Please run 'rails credentials:edit'."
    end

    commands = [
      { command: 'start', description: 'Start the bot and get a welcome message' },
      {command: 'help', description: 'Start the bot and get a help message'},
      {command: 'markspam', description: 'Mark a message as spam, then the bot will ban the sender and delete the spam message from group, only work in group chat'},
      {command: 'feedspam', description: 'Feed spam message to bot to help train the bot'},
      {command: 'listspam', description: 'List all banned users in the group, you could unban them manually'},
      {command: 'groupid', description: 'Get group id of current group'}
    ]
    begin
      require 'telegram/bot'
      api = Telegram::Bot::Api.new(token)
      response = api.set_my_commands(commands: commands)
      if response
        puts "Succeed to set commands"
      else
        puts "Failed to set commands: #{response['description']}"
      end
    rescue => e
      puts "An error occurred: #{e.message}"
    end
  end
end
