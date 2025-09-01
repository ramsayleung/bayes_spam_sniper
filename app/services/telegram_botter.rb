require "telegram/bot"

class TelegramBotter
  module CallbackConstants
    ACTION   = :a
    GROUP_ID = :gid
    USER_ID  = :uid
    PAGE     = :p
    LANGUAGE = :l
  end

  module CallbackAction
    USER_GUIDE = "user_guide"
    BACK_TO_MAIN = "back_to_main"
    LISTSPAM_PAGE = "listspam_page"
    UNBAN = "unban"
  end
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

    # Clean the message text and handle @botname mentions
    message_text = message.text&.strip || ""
    @lang_code = message.from.language_code || "en"
    # Remove @botname from the beginning if present
    message_text = message_text.gsub(/^@#{@bot_username}\s+/, "") if @bot_username

    # Route to appropriate command handler
    case message_text
    when %r{^/start}
      handle_start_command(bot, message)
    when %r{^/markspam}
      handle_markspam_command(bot, message)
    when %r{^/feedspam}
      handle_feedspam_command(bot, message, message_text)
    when %r{^/listspam}
      handle_listspam_command(bot, message)
    else
      handle_regular_message(bot, message)
    end
  rescue => e
    Rails.logger.error "An error occurred: #{e.message}\n#{e.backtrace.join("\n")}"
  end

  def handle_start_command(bot, message)
    keyboard = [
      [
        { text: I18n.t("telegram_bot.buttons.user_guide", locale: @lang_code),
          callback_data: build_callback_data(CallbackAction::USER_GUIDE, lang: @lang_code) },
        { text: I18n.t("telegram_bot.buttons.add_to_group", locale: @lang_code),
          url: "https://t.me/#{@bot_username}?startgroup=true" }
      ]
    ]

    # Build welcome message in both languages
    welcome_text = I18n.with_locale(@lang_code) do
      "#{I18n.t('telegram_bot.welcome.title')}\n\n" \
      "#{I18n.t('telegram_bot.welcome.description')}\n\n" \
      "#{I18n.t('telegram_bot.welcome.select_option')}"
    end


    bot.api.send_message(
      chat_id: message.chat.id,
      text: welcome_text,
      reply_markup: { inline_keyboard: keyboard }.to_json(),
      parse_mode: "Markdown"
    )
  end

  def handle_markspam_command(bot, message)
    return unless is_group_chat?(bot, message)
    return unless is_admin?(bot, message) && message.reply_to_message

    replied = message.reply_to_message
    return if replied.text.nil? || replied.text.empty?

    I18n.with_locale(@lang_code) do
      begin
        group_id = message.chat.id
        group_name = message.chat.title
        user_name = [ replied.from.first_name, replied.from.last_name ].compact.join(" ")
        # 1. Save the traineded message, which will invoke ActiveModel
        # hook to train the model in the background job
        trained_message = TrainedMessage.create!(
          group_id: group_id,
          message: replied.text,
          group_name: group_name,
          sender_chat_id: replied.from.id,
          sender_user_name: user_name,
          message_type: :spam
        )

        # 2. Ban user and record the ban
        bot.api.ban_chat_member(chat_id: message.chat.id, user_id: replied.from.id)
        banned_user_name = [ replied.from.first_name, replied.from.last_name ].compact.join(" ")
        BannedUser.find_or_create_by!(
          group_name: group_name,
          group_id: message.chat.id,
          sender_chat_id: replied.from.id,
          sender_user_name: banned_user_name,
          spam_message: replied.text
        )

        # 3. Delete the spam message
        bot.api.delete_message(chat_id: message.chat.id, message_id: replied.message_id)

        # 4. Confirm action
        response_message = I18n.t("telegram_bot.markspam.success_message", banned_user_name: banned_user_name, replied: replied)
        bot.api.send_message(chat_id: message.chat.id, text: response_message, parse_mode: "Markdown")
      rescue => e
        Rails.logger.error "Error in markspam command: #{e.message}"
        bot.api.send_message(chat_id: message.chat.id, text: I18n.t("telegram_bot.markspam.failure_message"))
      end
    end
  end

  def handle_feedspam_command(bot, message, message_text)
    # Extract everything after /feedspam command, preserving multiline content
    spam_text = message_text.sub(%r{^/feedspam\s*}, "").strip

    I18n.with_locale(@lang_code) do
      if spam_text.empty?
        help_message = <<~TEXT
      #{I18n.t('telegram_bot.feedspam.help_message')}
    TEXT
        bot.api.send_message(chat_id: message.chat.id, text: help_message, parse_mode: "Markdown")
        return
      end

      Rails.logger.info "spam message: #{message_text}"

      begin
        user_name = [ message.from.first_name, message.from.last_name ].compact.join(" ")
        chat_type = message.chat.type
        group_name = ""
        if chat_type == "private"
          group_name = "Private: " + user_name
        else
          group_name = message.chat.title
        end

        # Save the traineded message, which will invoke ActiveModel
        # hook to train the model in the background job
        trained_message = TrainedMessage.create!(
          group_id: message.chat.id,
          group_name: group_name,
          message: spam_text,
          sender_chat_id: message.from.id,
          sender_user_name: user_name,
          message_type: :untrained
        )

        # Show a preview of what was learned (truncated if too long)
        preview = spam_text.length > 100 ? "#{spam_text[0..100]}..." : spam_text
        response_message = I18n.t("telegram_bot.feedspam.success_message", preview: preview)
        bot.api.send_message(chat_id: message.chat.id, text: response_message, parse_mode: "Markdown")
      rescue => e
        Rails.logger.error "Error in feedspam command: #{e.message}"
        bot.api.send_message(chat_id: message.chat.id, text: "#{I18n.t('telegram_bot.feedspam.failure_message')}")
      end
    end
  end

  def is_admin?(bot, message)
    I18n.with_locale(@lang_code) do
      # Check if the user is admin of the target group
      unless is_admin_of_group?(bot: bot, user: message.from, group_id: message.chat.id)
        bot.api.send_message(
          chat_id: message.chat.id,
          text: I18n.t("telegram_bot.is_admin.error_message"),
        )
        return false
      end
      return true
    end
  end

  def handle_listspam_command(bot, message)
    return unless is_group_chat?(bot, message)
    return unless is_admin?(bot, message)

    # Parse the command: /listspam pageId
    command_parts = message.text.strip.split(/\s+/)

    target_group_id = message.chat.id
    group_title = message.chat.title
    page = command_parts[1].to_i > 0 ? command_parts[1].to_i : 1
    page = 1 if page < 1

    items_per_page = Rails.application.config.items_per_page
    offset = (page - 1) * items_per_page

    I18n.with_locale(@lang_code) do
      begin
        banned_users = BannedUser.where(group_id: target_group_id)
                         .order(created_at: :desc)
                         .offset(offset)
                         .limit(items_per_page)

        total_count = BannedUser.where(group_id: target_group_id).count
        total_pages = (total_count.to_f / items_per_page).ceil

        if banned_users.empty?
          if page == 1
            bot.api.send_message(
              chat_id: message.chat.id,
              text: "#{I18n.t('telegram_bot.listspam.no_banned_user_message')}",
              parse_mode: "Markdown"
            )
          else
            bot.api.send_message(
              chat_id: message.chat.id,
              text: I18n.t("telegram_bot.listspam.no_banned_on_page_x_message", group_title: group_title, page: page, target_group_id: target_group_id),
              parse_mode: "Markdown"
            )
          end
        else
          text = "🚫 **Banned Users** (Page #{page}/#{total_pages})\n"
          text += "Total banned users: #{total_count}\n\n"
          buttons = []

          max_spam_preview_length = Rails.application.config.max_spam_preview_length
          banned_users.each do |user|
            # Truncate long spam messages for display
            spam_preview = user.spam_message.length > max_spam_preview_length ? "#{user.spam_message[0..max_spam_preview_length]}..." : user.spam_message

            text += "**User:** *#{user.sender_user_name}*\n"
            text += "**Message:** `#{spam_preview}`\n"
            text += "**Banned:** #{user.created_at.strftime("%Y-%m-%d %H:%M")}\n\n"

            # Create an "unban" button for each user
            callback_data = build_callback_data(CallbackAction::UNBAN, CallbackConstants::USER_ID => user.id, CallbackConstants::GROUP_ID=> target_group_id)
            buttons << [ { text: "✅ #{I18n.t('telegram_bot.listspam.unban_message')} #{user.sender_user_name}", callback_data: callback_data } ]
          end

          # Add pagination buttons if needed
          pagination_buttons = []
          if page > 1
            pagination_buttons << { text: I18n.t("telegram_bot.listspam.previous_page"), callback_data: build_callback_data(CallbackAction::LISTSPAM_PAGE, CallbackConstants::GROUP_ID => target_group_id, CallbackConstants::PAGE => page - 1, CallbackConstants::LANGUAGE => @lang_code) }
          end
          if page < total_pages
            pagination_buttons << { text: I18n.t("telegram_bot.listspam.next_page"), callback_data: build_callback_data(CallbackAction::LISTSPAM_PAGE, CallbackConstants::GROUP_ID => target_group_id, CallbackConstants::PAGE => page + 1, CallbackConstants::LANGUAGE => @lang_code) }
          end

          buttons << pagination_buttons unless pagination_buttons.empty?

          reply_markup = { inline_keyboard: buttons }.to_json

          bot.api.send_message(
            chat_id: message.chat.id,
            text: text,
            reply_markup: reply_markup,
            parse_mode: "Markdown"
          )
        end
      rescue => e
        Rails.logger.error "Error in listspam command: #{e.message}"
        bot.api.send_message(chat_id: message.chat.id, text: "#{I18n.t('telegram_bot.listspam.unban_message')}")
      end
    end
  end

  def handle_regular_message(bot, message)
    return if message.text.nil? || message.text.strip.empty?

    I18n.with_locale(@lang_code) do
      begin
        classifier = SpamClassifierService.new(message.chat.id, message.chat.title)
        spam_message_text = message.text
        is_spam, spam_score, ham_score = classifier.classify(spam_message_text)
        # Spammer might leverage username as a way to send spam
        username = [ message.from.first_name, message.from.last_name ].compact.join(" ")
        username_classifier = SpamClassifierService.new(GroupClassifierState::USER_NAME_CLASSIFIER_GROUP_ID, GroupClassifierState::USER_NAME_CLASSIFIER_GROUP_NAME)
        username_is_spam, username_spam_score, username_ham_score = username_classifier.classify(username)

        if is_spam || username_is_spam
          bot.api.delete_message(chat_id: message.chat.id, message_id: message.message_id)
          alert_msg = I18n.t("telegram_bot.handle_regular_message.alert_message", user_name: username, user_id: message.from.id)
          bot.api.send_message(chat_id: message.chat.id, text: alert_msg, parse_mode: "Markdown")

          spam_ban_threshold = Rails.application.config.spam_ban_threshold
          user_id = message.from.id
          group_id = message.chat.id
          group_name = message.chat.title
          spam_count = TrainedMessage.where(group_id: group_id, sender_chat_id: user_id, message_type: :spam).count
          if spam_count >= (spam_ban_threshold - 1)
            Rails.logger.info "This user #{user_id} has sent spam message more than 3 times in group #{group_id}, ban it"
            bot.api.ban_chat_member(chat_id: group_id, user_id: user_id)
            banned_user_name = [ message.from.first_name, message.from.last_name ].compact.join(" ")
            BannedUser.find_or_create_by!(
              group_name: group_name,
              group_id: group_id,
              sender_chat_id: user_id,
              sender_user_name: banned_user_name,
              spam_message: spam_message_text,
              message_id: message.message_id
            )
            bot.api.send_message(chat_id: message.chat.id, text: I18n.t("telegram_bot.handle_regular_message.ban_user_message", user_name: username, user_id: message.from.id), parse_mode: "Markdown")
          end

          if is_spam
            TrainedMessage.create!(
              group_id: message.chat.id,
              group_name: message.chat.title,
              message: spam_message_text,
              training_target: :message_content,
              sender_chat_id: message.from.id,
              sender_user_name: username,
              message_type: :untrained,
              message_id: message.message_id
            )
          elsif username_is_spam
            TrainedMessage.create!(
              group_id: message.chat.id,
              group_name: message.chat.title,
              message: username,
              training_target: :user_name,
              sender_chat_id: message.from.id,
              sender_user_name: username,
              message_type: :untrained,
              message_id: message.message_id
            )
          end
        end
      rescue => e
        Rails.logger.error "Error processing regular message: #{e.message}"
      end
    end
  end

  def is_group_chat?(bot, message)
    I18n.with_locale(@lang_code) do
      # Returns true if the chat type is 'group' or 'supergroup'
      unless [ "group", "supergroup" ].include?(message.chat.type)
        bot.api.send_message(chat_id: message.chat.id, text: "#{I18n.t('telegram_bot.is_group_chat.error_message')}", parse_mode: "Markdown")
        return false
      end
      return true
    end
  end

  def is_admin_of_group?(bot:, user:, group_id:)
    # If the admin is a bot
    return true if user.is_bot && user.username == "GroupAnonymousBot"

    # TODO: This API call can be rate-limited. Cache results in production.
    begin
      admins = bot.api.get_chat_administrators(chat_id: group_id.to_s)

      admins.any? { |admin| admin.user.id == user.id }
    rescue => e
      Rails.logger.error "Error during admin check for chat #{group_id}. Error: #{e.message}"
      false
    end
  end

  def handle_callback(bot, callback)
    Rails.logger.info "Handling callback"

    callback_data = parse_callback_data(callback.data)
    action = callback_data[CallbackConstants::ACTION]
    user_id = callback_data[CallbackConstants::USER_ID]
    @lang_code = callback_data[CallbackConstants::LANGUAGE] || "en"
    page = callback_data[CallbackConstants::PAGE] || 1

    chat_id = callback.message.chat.id
    message_id = callback.message.message_id
    I18n.with_locale(@lang_code) do
      case action
      when CallbackAction::USER_GUIDE
        handle_user_guide_callback(bot, callback)
      when CallbackAction::UNBAN
        handle_unban_callback(bot, callback, chat_id, message_id, user_id)
      when CallbackAction::LISTSPAM_PAGE
        handle_listspam_pagination_callback(bot, callback, page)
      when CallbackAction::BACK_TO_MAIN
        handle_back_to_main_callback(bot, callback)
      end
      rescue => e
        Rails.logger.info "Error handling callback: #{e.message}\n#{e.backtrace.join("\n")}"
        bot.api.send_message(chat_id: chat_id, text: "#{I18n.t('telegram_bot.handle_callback.error_message')}")
    end
  end

  def handle_back_to_main_callback(bot, callback)
    handle_start_command(bot, callback.message)
    bot.api.answer_callback_query(callback_query_id: callback.id)
  end

  def handle_user_guide_callback(bot, callback)
    I18n.with_locale(@lang_code) do
      steps = I18n.t("telegram_bot.user_guide.steps", bot_username: @bot_username)
                .map.with_index(1) { |step, i| "#{i}. #{step}" }
                .join("\n")

      features = I18n.t("telegram_bot.user_guide.features")
                   .map { |feature| "• #{feature}" }
                   .join("\n")

      commands = I18n.t("telegram_bot.user_guide.commands").values.join("\n")

      usage_text = <<~TEXT
      #{I18n.t('telegram_bot.user_guide.title')}

      #{I18n.t('telegram_bot.user_guide.how_to_use')}
      #{steps}

      #{I18n.t('telegram_bot.user_guide.basic_features')}
      #{features}

      #{I18n.t('telegram_bot.user_guide.commands_title')}
      #{commands}

      #{I18n.t('telegram_bot.user_guide.support')}
    TEXT

      bot.api.edit_message_text(
        chat_id: callback.message.chat.id,
        message_id: callback.message.message_id,
        text: usage_text,
        parse_mode: "Markdown",
        reply_markup: {
          inline_keyboard: [ [
                               { text: "← #{I18n.t('telegram_bot.buttons.back')}",
                                 callback_data: build_callback_data(CallbackAction::BACK_TO_MAIN, CallbackConstants::LANGUAGE => @lang_code) }
                             ] ]
        }.to_json()
      )
    end

    bot.api.answer_callback_query(callback_query_id: callback.id)
  end

  def handle_unban_callback(bot, callback, chat_id, message_id, banned_user_id)
    # Only admin has permission to perform actions
    return unless is_admin_of_group?(bot: bot, user: callback.from, group_id: callback.message.chat.id)

    I18n.with_locale(@lang_code) do
      banned_user = BannedUser.find_by(id: banned_user_id)
      # The user is already unbanned
      unless banned_user
        return edit_message_text(bot, chat_id, message_id, I18n.t("telegram_bot.unban.already_unbanned_message"))
      end

      begin
        messages_to_retrain = TrainedMessage.where(
          group_id: chat_id,
          sender_chat_id: banned_user.sender_chat_id,
          message_type: :spam
        )
        # This will trigger ActiveModel hook to automatically rebuild
        # classifier in a background job
        messages_to_retrain.update!(message_type: :ham)
        begin
          bot.api.unban_chat_member(chat_id: chat_id, user_id: banned_user.sender_chat_id)
        rescue => e
          Rails.logger.error "Failed to unbanning user #{banned_user.send_chat_id} due to: #{e.message}"
        end

        user_name = banned_user.sender_user_name
        user_id = banned_user.sender_chat_id
        banned_user.destroy!

        edit_message_text(bot, chat_id, message_id, I18n.t("telegram_bot.unban.success_message", user_name: user_name, user_id: user_id))
      rescue => e
        Rails.logger.error "Error unbanning user: #{e.message}"
      end
    end
  end

  def handle_listspam_pagination_callback(bot, callback, page)
    # Only admin has permission to perform actions
    is_admin = is_admin_of_group?(bot: bot, user: callback.from, group_id: callback.message.chat.id)
    return unless is_admin

    # Simulate the listspam command with the new page
    callback_data = parse_callback_data(callback.data)
    group_id = callback_data[CallbackConstants::GROUP_ID]

    fake_message = Struct.new(:text, :chat, :from).new(
      text: "/listspam #{page}",
      chat: callback.message.chat,
      from: callback.from
    )

    # Delete the old message
    bot.api.delete_message(chat_id: callback.message.chat.id, message_id: callback.message.message_id)

    # Send new message with updated page
    handle_listspam_command(bot, fake_message)
  end

  def build_callback_data(action, **params)
    # Telegram's API has a strict limit: callback_data strings must be between 1 and 64 bytes.
    data = { CallbackConstants::ACTION => action }
    data.merge!(params) if params.any?
    data.to_json
  end

  def parse_callback_data(callback_data)
    JSON.parse(callback_data).with_indifferent_access
  rescue JSON::ParserError
    # Fallback for old format "action:param"
    parts = callback_data.split(":", 2)
    { action: parts[0], param: parts[1] }
  end

  def edit_message_text(bot, chat_id, message_id, new_text)
    bot.api.edit_message_text(
      chat_id: chat_id,
      message_id: message_id,
      text: new_text,
      parse_mode: "Markdown"
    )
  rescue => e
    Rails.logger.error "Error editing message: #{e.message}"
    # If editing fails, send a new message
    bot.api.send_message(chat_id: chat_id, text: new_text, parse_mode: "Markdown")
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
