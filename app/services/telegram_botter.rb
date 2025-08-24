require 'telegram/bot'

class TelegramBotter
  def start_bot(token)
   
    Telegram::Bot::Client.run(token) do |bot|
      Rails.application.config.telegram_bot = bot
      # Get bot username for @ mentions
      @bot_username ||= bot.api.get_me.username
      Rails.application.config.telegram_bot_name = @bot_username
      # Get latest message
      bot.api.get_updates(offset: -1)

      bot.listen do |message_or_callback|
        Rails.logger.info "Bot is listening..."
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

  private

  def handle_message(bot, message)
    Rails.logger.info "Handling message"

    is_admin = is_admin?(bot: bot, user: message.from, chat: message.chat)
  
    # Clean the message text and handle @botname mentions
    message_text = message.text&.strip || ""
  
    # Remove @botname from the beginning if present
    message_text = message_text.gsub(/^@#{@bot_username}\s+/, '') if @bot_username
  
    # Route to appropriate command handler
    case message_text
    when %r{^/start}
      handle_start_command(bot, message)
    when %r{^/markspam}
      handle_markspam_command(bot, message, is_admin)
    when %r{^/feedspam}
      handle_feedspam_command(bot, message, is_admin, message_text)
    when %r{^/listspam}
      handle_listspam_command(bot, message, is_admin)
    else
      handle_regular_message(bot, message)
    end
  rescue => e
    Rails.logger.error "An error occurred: #{e.message}\n#{e.backtrace.join("\n")}"
  end

  def handle_start_command(bot, message)
    start_message = "Hello! I am a spam detection bot. Add me to your group and promote me to an admin with 'Ban Users' and 'Delete Messages' permissions to get started!"
    bot.api.send_message(chat_id: message.chat.id, text: start_message)
  end

  def handle_markspam_command(bot, message, is_admin)
    return unless is_admin && message.reply_to_message

    replied = message.reply_to_message
    return if replied.text.nil? || replied.text.empty?

    begin
      group_id = message.chat.id
      user_name = [replied.from.first_name, replied.from.last_name].compact.join(" ")
      # 1. Save the traineded message, which will invoke ActiveModel
      # hook to train the model in the background job
      trained_message = TrainedMessage.create!(
        group_id: group_id,
        message: replied.text,
        sender_chat_id: replied.from.id,
        sender_user_name: user_name,
        message_type: :spam
      )

      # 2. Ban user and record the ban
      bot.api.ban_chat_member(chat_id: message.chat.id, user_id: replied.from.id)
      banned_user_name = [replied.from.first_name, replied.from.last_name].compact.join(" ")
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
    rescue => e
      Rails.logger.error "Error in markspam command: #{e.message}"
      bot.api.send_message(chat_id: message.chat.id, text: "❌ Failed to process the spam marking request.")
    end
  end

  def handle_feedspam_command(bot, message, is_admin, message_text)
    return unless is_admin

    # Extract everything after /feedspam command, preserving multiline content
    spam_text = message_text.sub(%r{^/feedspam\s*}, '').strip
  
    if spam_text.empty?
      help_message = <<~TEXT
      Please provide the spam message text after the command. 
      
      Examples:
      `/feedspam FREE IPHONE`
    TEXT
      bot.api.send_message(chat_id: message.chat.id, text: help_message, parse_mode: 'Markdown')
      return
    end

    Rails.logger.info "spam message: #{message_text}"

    begin
      user_name = [message.from.first_name, message.from.last_name].compact.join(" ")

      # Save the traineded message, which will invoke ActiveModel
      # hook to train the model in the background job
      trained_message = TrainedMessage.create!(
        group_id: message.chat.id,
        message: spam_text,
        sender_chat_id: message.from.id,
        sender_user_name: user_name,
        message_type: :spam
      )
    
      # Show a preview of what was learned (truncated if too long)
      preview = spam_text.length > 100 ? "#{spam_text[0..100]}..." : spam_text
      response_message = "✅ Got it. I've learned from that spam message:\n\n`#{preview}`"
      bot.api.send_message(chat_id: message.chat.id, text: response_message, parse_mode: 'Markdown')
    rescue => e
      Rails.logger.error "Error in feedspam command: #{e.message}"
      bot.api.send_message(chat_id: message.chat.id, text: "❌ Failed to process the spam training request.")
    end
  end

  def handle_listspam_command(bot, message, is_admin)
    return unless is_admin

    # Parse the page number from the command, defaulting to 1
    page_match = message.text.match(%r{^/listspam\s+(\d+)})
    page = page_match ? page_match[1].to_i : 1
    page = 1 if page < 1
  
    items_per_page = 10
    offset = (page - 1) * items_per_page

    begin
      banned_users = BannedUser.where(group_id: message.chat.id)
                       .order(created_at: :desc)
                       .offset(offset)
                       .limit(items_per_page)

      total_count = BannedUser.where(group_id: message.chat.id).count
      total_pages = (total_count.to_f / items_per_page).ceil

      if banned_users.empty?
        if page == 1
          bot.api.send_message(
            chat_id: message.chat.id,
            text: "There are no banned users in this group."
          )
        else
          bot.api.send_message(
            chat_id: message.chat.id,
            text: "No banned users found on page #{page}. Try `/listspam 1` to see the first page.",
            parse_mode: 'Markdown'
          )
        end
      else
        text = "🚫 **Banned Users** (Page #{page}/#{total_pages})\n"
        text += "Total banned users: #{total_count}\n\n"
        buttons = []

        banned_users.each do |user|
          # Truncate long spam messages for display
          spam_preview = user.spam_message.length > 50 ? "#{user.spam_message[0..50]}..." : user.spam_message
        
          text += "**User:** #{user.sender_user_name}\n"
          text += "**Message:** #{spam_preview}\n"
          text += "**Banned:** #{user.created_at.strftime("%Y-%m-%d %H:%M")}\n\n"

          # Create an "unban" button for each user
          callback_data = build_callback_data('unban', user_id: user.id)
          buttons << [{ text: "✅ Unban #{user.sender_user_name}", callback_data: callback_data }]
        end

        # Add pagination buttons if needed
        pagination_buttons = []
        if page > 1
          pagination_buttons << { text: "⬅️ Previous", callback_data: "listspam:#{page - 1}" }
        end
        if page < total_pages
          pagination_buttons << { text: "Next ➡️", callback_data: "listspam:#{page + 1}" }
        end
      
        buttons << pagination_buttons unless pagination_buttons.empty?

        reply_markup = { inline_keyboard: buttons }.to_json

        bot.api.send_message(
          chat_id: message.chat.id,
          text: text,
          reply_markup: reply_markup,
          parse_mode: 'Markdown'
        )
      end
    rescue => e
      Rails.logger.error "Error in listspam command: #{e.message}"
      bot.api.send_message(chat_id: message.chat.id, text: "❌ Failed to retrieve banned users list.")
    end
  end

  def handle_regular_message(bot, message)
    return if message.text.nil? || message.text.strip.empty?

    begin
      classifier = SpamClassifierService.new(message.chat.id)
      is_spam, spam_score, ham_score = classifier.classify(message.text)
      Rails.logger.info "is_spam:#{is_spam}, spam_score: #{spam_score}, ham_score: #{ham_score}"

      if is_spam
        bot.api.delete_message(chat_id: message.chat.id, message_id: message.message_id)
        user_name = [message.from.first_name, message.from.last_name].compact.join(" ")
        alert_msg = "⚠️ Potential spam detected from @[#{user_name}](tg://user?id=#{message.from.id}) and removed."
        Rails.logger.info alert_msg
        bot.api.send_message(chat_id: message.chat.id, text: alert_msg, parse_mode: 'Markdown')
      end
    rescue => e
      Rails.logger.error "Error processing regular message: #{e.message}"
    end
  end
  
  def is_admin?(bot:, user:, chat:)
    # If the admin is a bot
    return true if user.is_bot && user.username == 'GroupAnonymousBot'

    # TODO: This API call can be rate-limited. Cache results in production.
    begin
      admins = bot.api.get_chat_administrators(chat_id: chat.id.to_s)
    
      return admins.any? { |admin| admin.user.id == user.id }
    rescue => e
      Rails.logger.error "Error during admin check for chat #{chat.id}. Error: #{e.message}"
      return false
    end
  end

  def handle_callback(bot, callback)
    Rails.logger.info "Handling callback"

    # Only admin has permission to perform actions
    return unless is_admin?(bot: bot, user: callback.from, chat: callback.message.chat)

    callback_data = parse_callback_data(callback.data)
    action = callback_data[:action]
    user_id = callback_data[:user_id]

    chat_id = callback.message.chat.id
    message_id = callback.message.message_id
    case action
    when 'unban'
      handle_unban_callback(bot, chat_id, message_id, user_id)
    when 'listspam'
      handle_listspam_pagination_callback(bot, callback, user_id.to_i)
    end
  rescue => e
    Rails.logger.info "Error handling callback: #{e.message}\n#{e.backtrace.join("\n")}"
    bot.api.send_message(chat_id: chat_id, text: "An error occurred while processing your request.")
  end

  def handle_unban_callback(bot, chat_id, message_id, banned_user_id)
    banned_user = BannedUser.find_by(id: banned_user_id)

    # If the user is already unbanned, just update the message
    return edit_message_text(bot, chat_id, message_id, "This user has already been unbanned.") unless banned_user

    begin
      messages_to_retrain = TrainedMessage.where(
        group_id: chat_id,
        sender_chat_id: banned_user.sender_chat_id,
        message_type: :spam
      )
      # This will trigger ActiveModel hook to automatically rebuild
      # classifier in a background job
      messages_to_retrain.update!(message_type: :ham)

      bot.api.unban_chat_member(chat_id: chat_id, user_id: banned_user.sender_chat_id)

      user_name = banned_user.sender_user_name
      user_id = banned_user.sender_chat_id
      banned_user.destroy!
    
      edit_message_text(bot, chat_id, message_id, "✅ User @[#{user_name}](tg://user?id=#{user_id}) has been unbanned and their messages marked as ham.")
    rescue => e
      Rails.logger.error "Error unbanning user: #{e.message}"
      edit_message_text(bot, chat_id, message_id, "❌ Failed to unban user.")
    end
  end

  def handle_listspam_pagination_callback(bot, callback, page)
    # Simulate the listspam command with the new page
    fake_message = OpenStruct.new(
      text: "/listspam #{page}",
      chat: callback.message.chat,
      from: callback.from
    )
  
    is_admin = is_admin?(bot: bot, user: callback.from, chat: callback.message.chat)
  
    # Delete the old message
    bot.api.delete_message(chat_id: callback.message.chat.id, message_id: callback.message.message_id)
  
    # Send new message with updated page
    handle_listspam_command(bot, fake_message, is_admin)
  end

  def build_callback_data(action, **params)
    data = { action: action }
    data.merge!(params) if params.any?
    data.to_json
  end

  def parse_callback_data(callback_data)
    JSON.parse(callback_data).with_indifferent_access
  rescue JSON::ParserError
    # Fallback for old format "action:param"
    parts = callback_data.split(':', 2)
    { action: parts[0], param: parts[1] }
  end

  def edit_message_text(bot, chat_id, message_id, new_text)
    bot.api.edit_message_text(
      chat_id: chat_id,
      message_id: message_id,
      text: new_text,
      parse_mode: 'Markdown'
    )
  rescue => e
    Rails.logger.error "Error editing message: #{e.message}"
    # If editing fails, send a new message
    bot.api.send_message(chat_id: chat_id, text: new_text, parse_mode: 'Markdown')
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
