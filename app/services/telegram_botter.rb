require 'telegram/bot'

class TelegramBotter
  def start_bot(token)
   
    Telegram::Bot::Client.run(token) do |bot|
      Rails.application.config.telegram_bot = bot
      # Get latest message
      bot.api.get_updates(offset: -1)

      bot.listen do |message_or_callback|
        puts "Bot is listening..."
        case message_or_callback
        when Telegram::Bot::Types::Message
          handle_message(bot, message_or_callback)
        when Telegram::Bot::Types::CallbackQuery
          handle_callback(bot, message_or_callback)
        end
      end
    end
  rescue Telegram::Bot::Exceptions::ResponseError => e
    Rails.logger.error e
    Rails.application.config.telegram_bot.stop
    Rails.application.config.telegram_bot.api.delete_webhook
  end

  def is_admin?(bot:, user:, chat:)
    # If the admin is a bot
    return true if user.is_bot && user.username == 'GroupAnonymousBot'

    begin
      admins = bot.api.get_chat_administrators(chat_id: chat.id.to_s)
    
      return admins.any? { |admin| admin.user.id == user.id }
    rescue => e
      puts "Error during admin check for chat #{chat.id}. Error: #{e.message}"
      puts "chat: #{chat.inspect}, user: #{user.inspect}"
      return false
    end
  end


  def handle_message(bot, message)
    Rails.logger.info "Handling message"
  
    # Check if the user is an admin (we'll need this for protected commands)
    # TODO: This API call can be rate-limited. Cache results in production.
    is_admin = is_admin?(bot: bot, user: message.from, chat: message.chat)
    case message.text
    when %r{^/start}
      start_message = "Hello! I am a spam detection bot. Add me to your group..."
      bot.api.send_message(chat_id: message.chat.id, text: start_message)

    when %r{^/markspam}
      puts "is_admin: #{is_admin}, message.reply_to_message: #{message.reply_to_message}"
      return unless is_admin && message.reply_to_message
    
      replied = message.reply_to_message
      return if replied.text.nil? || replied.text.empty?

      # 1. Train the model
      classifier = SpamClassifierService.new(message.chat.id)
      user_name = [replied.from.first_name, replied.from.last_name].join(" ")
      classifier.train(replied.text, replied.from.id, user_name, :spam)

      # 2. Ban user and record the ban
      bot.api.ban_chat_member(chat_id: message.chat.id, user_id: replied.from.id)
      banned_user_name = [replied.from.first_name, replied.from.last_name].join(" ")
      BannedUser.find_or_create_by!(
        group_id: message.chat.id,
        sender_chat_id: replied.from.id,
        sender_user_name: banned_user_name,
        spam_message: replied.text
      )

      # 3. Delete the spam message
      bot.api.delete_message(chat_id: message.chat.id, message_id: replied.message_id)

      # 4. Confirm action
      response_message = "✅ User @[#{banned_user_name}](tg://user?id=#{replied.from.id}) has been banned and the message marked as spam."
      bot.api.send_message(chat_id: message.chat.id, text: response_message, parse_mode: 'Markdown')

    when %r{^/feedspam(?: (.+))?$}
      return unless is_admin
    
      spam_text = $1 # Text captured from the command, e.g., /feedspam some spam text
      if spam_text.nil? || spam_text.strip.empty?
        bot.api.send_message(chat_id: message.chat.id, text: "Please provide the spam message text after the command. Example: `/feedspam buy cheap stuff now`")
        return
      end

      classifier = SpamClassifierService.new(message.chat.id)
      classifier.train(spam_text, message.from.id, [message.from.first_name, message.from.last_name].join(" "), :spam)
      bot.api.send_message(chat_id: message.chat.id, text: "✅ Got it. I've learned from that spam message.")
    when %r{^/listspam}
      return unless is_admin
    
      # 1. Parse the page number from the command, defaulting to 1
      page = ($1 || 1).to_i
      items_per_page = 10
      offset = (page - 1) * items_per_page
    
      # 2. Query the database for banned users with pagination
      banned_users = BannedUser.where(group_id: message.chat.id)
                       .order(created_at: :desc)
                       .offset(offset)
                       .limit(items_per_page)

      # 3. Format the response message
      if banned_users.empty?
        bot.api.send_message(
          chat_id: message.chat.id,
          text: "There are no banned users in this group."
        )
      else
        text = "🚫 **Banned Users** (Page #{page})\n\n"
        buttons = []
      
        banned_users.each do |user|
          text += "User: #{user.sender_user_name}\n"
          text += "Spam Message: #{user.spam_message}\n"
          text += "Banned on: #{user.created_at.strftime("%Y-%m-%d %H:%M")}\n\n"
        
          # Create an "unban" button for each user
          callback_data = "unban:#{user.id}"
          buttons << [{ text: "✅ Unban #{user.sender_user_name}", callback_data: callback_data }]
        end
      
        # Prepare the reply markup with all the buttons
        reply_markup = { inline_keyboard: buttons }.to_json

        # 4. Send the message with the list and interactive buttons
        bot.api.send_message(
          chat_id: message.chat.id,
          text: text,
          reply_markup: reply_markup,
          parse_mode: 'Markdown'
        )
      end

    else
      return if message.text.nil? || message.text.strip.empty?
    
      classifier = SpamClassifierService.new(message.chat.id)
      is_spam, spam_score, ham_score = classifier.classify(message.text)
      Rails.logger.info "is_spam:#{is_spam}, spam_score: #{spam_score}, ham_score: #{ham_score}"
    
      if is_spam
        bot.api.delete_message(chat_id: message.chat.id, message_id: message.message_id)
        alert_msg = "⚠️ Potential spam detected from @[#{[message.from.first_name, message.from.last_name].join(" ")}](tg://user?id=#{message.from.id}) and removed."
        Rails.logger.info alert_msg
        bot.api.send_message(chat_id: message.chat.id, text: alert_msg, parse_mode: 'Markdown')
      end
    end
  rescue => e
    puts "An error occurred: #{e.message}\n#{e.backtrace.join("\n")}"
  end

  def edit_message_text(bot, chat_id, message_id, text)
    bot.api.edit_message_text(chat_id: chat_id, message_id: message_id, text: text, parse_mode: 'Markdown')
  end

  def handle_callback(bot, callback)
    Rails.logger.info "Handling callback"

    chat_id = callback.message.chat.id
    message_id = callback.message.message_id
    data = callback.data

    is_admin = is_admin?(bot: bot, user: callback.from, chat: callback.message.chat)

    # First, check if the user clicking the button is an admin
    return unless is_admin
  
    # Parse the callback data (e.g., "unban:123")
    action, banned_user_id = data.split(':')

    case action
    when 'unban'
      banned_user = BannedUser.find_by(id: banned_user_id)
    
      # If the user is already unbanned, just update the message
      return edit_message_text(bot, chat_id, message_id, "This user has already been unbanned.") unless banned_user

      # Find all spam messages from this user
      messages_to_retrain = TrainedMessage.where(
        group_id: chat_id, 
        sender_chat_id: banned_user.sender_chat_id,
        message_type: :spam
      )
    
      classifier = SpamClassifierService.new(chat_id)
      classifier.retrain_as_ham(messages_to_retrain)
    
      bot.api.unban_chat_member(chat_id: chat_id, user_id: banned_user.sender_chat_id)
    
      # Delete the banned user record from the database
      banned_user.destroy!
      edit_message_text(bot, chat_id, message_id, "✅ User @[#{banned_user.sender_user_name}](tg://user?id=#{banned_user.sender_chat_id}) has been unbanned and their messages marked as ham.")
    end
  rescue => e
    puts "Error handling callback: #{e.message}\n#{e.backtrace.join("\n")}"
    bot.api.send_message(chat_id: chat_id, text: "An error occurred while processing your request: #{e.message}")
  end

  Signal.trap("TERM") do
    puts "Shutting down bot..."
    Rails.application.config.telegram_bot.stop
    exit
  end

  Signal.trap("INT") do
    puts "Shutting down bot..."
    Rails.application.config.telegram_bot.stop
    exit
  end
end
