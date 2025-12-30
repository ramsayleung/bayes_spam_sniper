require "telegram/bot"
require "prometheus/client"
require "ostruct"

class TelegramBotter
  include PrometheusMetrics
  module CallbackConstants
    ACTION   = :a
    GROUP_ID = :gid
    USER_ID  = :uid
    PAGE     = :p
    LANGUAGE = :l
    TRAINED_MESSAGE_ID = :tmid
  end

  module CallbackAction
    USER_GUIDE = "ug"
    BACK_TO_MAIN = "btm"
    LISTBANUSER_PAGE = "lbp"
    LISTSPAM_PAGE = "lsp"
    UNBAN = "unban"
    MARK_AS_HAM = "mah"
  end
  def start_bot(token)
    Telegram::Bot::Client.run(token) do |bot|
      Rails.application.config.telegram_bot = bot
      # Get bot username for @ mentions
      get_me_result ||= bot.api.get_me
      @bot_username ||= Rails.cache.fetch("bot_username", expires_in: 24.hours) do
        get_me_result.username
      end
      @bot_id ||= Rails.cache.fetch("bot_id", expires_in: 24.hours) do
        get_me_result.id
      end
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

  # Determines the appropriate language code for a given message based on a layered approach.
  # 1. Checks for a group-specific language setting if it's a group message.
  # 2. Falls back to the sender's language code from their Telegram profile.
  # 3. Defaults to 'en' if no language is determined.
  def determine_language(message)
    # 1. Check for group-specific language setting
    if is_group_message?(message)
      group_state = GroupClassifierState.find_by(group_id: message.chat.id)
      return group_state.language if group_state&.language.present?
    end

    # 2. Fallback to user's language_code from Telegram
    if message.from&.language_code.present?
      return message.from.language_code.split("-").first
    end

    # 3. Default to 'en'
    "en"
  end

  def handle_message(bot, message)
    message_text = message.text&.strip || ""
    Rails.logger.info "Handling message #{message.to_h.to_json}"

    # In group chats, ignore commands for other bots
    if is_group_message?(message)
      command_match = message_text.match(%r{^/([a-zA-Z0-9_]+)(?:@([a-zA-Z0-9_]+))?})
      if command_match
        target_bot = command_match[2]
        # If the command is targeted at a specific bot, and it's not this one, ignore it
        if target_bot && target_bot.casecmp(@bot_username) != 0
          Rails.logger.info "Ignoring command for another bot: #{message_text}"
          return
        end
      end
    end

    username = [ message.from&.first_name, message.from&.last_name ].compact.join(" ")
    @lang_code = determine_language(message)

    # Remove @botname from the beginning if present
    message_text = message_text.gsub(/^@#{@bot_username}\s+/, "") if @bot_username
    if @bot_username
      bot_mention_regex = /@#{@bot_username}/i

      # Command with bot name appended (e.g., /feedspam@BotName)
      # This strips the @BotName from the end of the command.
      message_text = message_text.gsub(bot_mention_regex, "")
    end

    # Route to appropriate command handler and track command usage
    case message_text
    when %r{^/start}
      handle_start_command(bot, message)
    when %r{^/setlang}
      increment_command_counter("setlang")
      handle_set_language_command(bot, message)
    when %r{^/markspam}
      increment_command_counter("markspam")
      handle_markspam_command(bot, message)
    when %r{^/feedspam}
      increment_command_counter("feedspam")
      handle_feedspam_command(bot, message, message_text)
    when %r{^/listbanuser}
      increment_command_counter("listbanuser")
      handle_listbanuser_command(bot, message)
    when %r{^/listspam}
      increment_command_counter("listspam")
      handle_listspam_command(bot, message)
    else
      if reply_to_bot?(message)
        # If it's a reply, check if it's meant for the bot's training prompt
        handle_forced_reply(bot, message)
      else
        handle_regular_message(bot, message)
      end
    end
  rescue => e
    Rails.logger.error "An error occurred: #{e.message}\n#{e.backtrace.join("\n")}"
  end

  def handle_start_command(bot, message)
    keyboard = [
      [
        { text: I18n.t("telegram_bot.buttons.user_guide", locale: @lang_code),
          callback_data: build_callback_data(CallbackAction::USER_GUIDE, CallbackConstants::LANGUAGE => @lang_code) },
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

  def handle_set_language_command(bot, message)
    return unless is_group_chat?(bot, message)
    return unless is_admin?(bot, user: message.from, group_id: message.chat.id)

    I18n.with_locale(@lang_code) do
      command_parts = message.text.strip.split(/\s+/)
      target_language = command_parts[1]&.downcase

      if target_language.nil?
        bot.api.send_message(
          chat_id: message.chat.id,
          text: I18n.t("telegram_bot.setlang.usage", available_locales: I18n.available_locales.map(&:to_s).join(", ")),
        )
        return
      end

      if I18n.available_locales.map(&:to_s).include?(target_language)
        group_id = message.chat.id
        group_name = message.chat.title || "Unknown Group"

        service = SpamClassifierService.new(group_id, group_name)
        group_state = service.classifier_state
        group_state.language = target_language

        if group_state.save
          bot.api.send_message(
            chat_id: message.chat.id,
            text: I18n.t("telegram_bot.setlang.success", language: target_language),
          )
        else
          Rails.logger.error "Error saving group language: #{group_state.errors.full_messages.join(', ')}"
          bot.api.send_message(
            chat_id: message.chat.id,
            text: I18n.t("telegram_bot.setlang.failure"),
          )
        end
      else
        bot.api.send_message(
          chat_id: message.chat.id,
          text: I18n.t("telegram_bot.setlang.unsupported_language", language: target_language, available_locales: I18n.available_locales.map(&:to_s).join(", ")),
        )
      end
    end
  rescue => e
    Rails.logger.error "Error in setlang command: #{e.message}\n#{e.backtrace.join("\n")}"
    bot.api.send_message(chat_id: message.chat.id, text: I18n.t("telegram_bot.setlang.general_error"))
  end

  def handle_markspam_command(bot, message)
    Rails.logger.info "Handling markspam: #{message.to_h.to_json}"
    return unless is_group_chat?(bot, message)
    return unless is_admin?(bot, user: message.from, group_id: message.chat.id)
    return if message.reply_to_message.nil?

    group_id = message.chat.id
    chat_member = TelegramMemberFetcher.get_bot_chat_member(group_id)
    # return if bot is not admin
    return unless [ "administrator", "creator" ].include?(chat_member.status) && message.reply_to_message

    replied = message.reply_to_message
    spam_text = extract_searchable_content(message.reply_to_message)
    return if spam_text.nil? || spam_text.empty?

    signals = extract_signals(message.reply_to_message)
    if signals.any?
      spam_text = spam_text + " " + signals.join(" ")
    end

    I18n.with_locale(@lang_code) do
      begin
        group_name = message.chat.title
        user_name = [ replied.from&.first_name, replied.from&.last_name ].compact.join(" ")
        # 1. Save the traineded message, which will invoke ActiveModel
        # hook to train the model in the background job
        trained_message = TrainedMessage.create!(
          group_id: group_id,
          message: spam_text,
          group_name: group_name,
          sender_chat_id: replied.from.id,
          sender_user_name: user_name,
          message_type: :spam,
          marked_by: :group_admin
        )
        can_delete_messages = chat_member.can_delete_messages
        can_restrict_members = chat_member.can_restrict_members

        # 2. Delete the spam message
        unless can_delete_messages
          response_message = I18n.t("telegram_bot.markspam.insufficient_permission_to_delete_message")
          bot.api.send_message(chat_id: message.chat.id, text: response_message, parse_mode: "Markdown")
          return
        end
        bot.api.delete_message(chat_id: message.chat.id, message_id: replied.message_id)

        # 3. Ban user and record the ban
        banned_user_name = [ replied.from&.first_name, replied.from&.last_name ].compact.join(" ")
        if can_restrict_members
          bot.api.ban_chat_member(chat_id: message.chat.id, user_id: replied.from.id)
          BannedUser.find_or_create_by!(
            group_name: group_name,
            group_id: message.chat.id,
            sender_chat_id: replied.from.id,
            sender_user_name: banned_user_name,
            spam_message: spam_text
          )
        end

        # 4. Confirm action
        response_message = ""
        if !can_restrict_members
          response_message = I18n.t("telegram_bot.markspam.delete_message_only_success_message", banned_user_name: banned_user_name, user_id: replied.from.id)
        else
          response_message = I18n.t("telegram_bot.markspam.success_message", banned_user_name: banned_user_name, user_id: replied.from.id)
        end

        sent_message = bot.api.send_message(chat_id: message.chat.id, text: response_message, parse_mode: "Markdown")
        # 5. Schedule a background job to delete the message
        # to avoid polluting the group chat
        delete_message_delay = Rails.application.config.delete_message_delay
        TelegramBackgroundWorkerJob.set(wait: delete_message_delay.minutes).perform_later(
          action: PostAction::DELETE_ALERT_MESSAGE,
          chat_id: sent_message.chat.id,
          message_id: sent_message.message_id)
      rescue => e
        Rails.logger.error "Error in markspam command: #{e.message}"
        bot.api.send_message(chat_id: message.chat.id, text: I18n.t("telegram_bot.markspam.failure_message"))
      end
    end
  end

  def handle_forced_reply(bot, message)
    replied_to = message.reply_to_message

    # 1. Ensure it's a reply to a message sent by the bot
    return unless reply_to_bot?(message)

    Rails.logger.info "handle_forced_reply: #{replied_to.text}"

    # 2. Check if the bot's message was the /feedspam prompt.
    # defined in I18n.t('telegram_bot.feedspam.reply_prompt', locale: @lang_code)
    feedspam_expected_prefix = "/feedspam:"
    if replied_to.text&.start_with?(feedspam_expected_prefix)
      spam_text = message.text&.strip
      if spam_text.nil? || spam_text.empty?
        # User replied with an empty message
        bot.api.send_message(
          chat_id: message.chat.id,
          text: I18n.t("telegram_bot.feedspam.empty_reply_error", locale: @lang_code),
          reply_to_message_id: message.message_id # Reply to the empty reply to show who made the mistake
        )
      else
        # Reroute to the actual training logic
        execute_spam_training(bot, message, spam_text)
      end
    end
  end

  def handle_feedspam_command(bot, message, message_text)
    I18n.with_locale(@lang_code) do
      # 1. Check if the command was used as a reply to another message
      replied_message = message.reply_to_message

      if replied_message && !replied_message.text.to_s.strip.empty?
        Rails.logger.info "It's replied_message in feedspam"
        # Use the text of the replied-to message for training
        spam_text = replied_message.text

        # Execute training logic
        execute_spam_training(bot, message, spam_text)

      else
        Rails.logger.info "It's not replied_message in feedspam"
        # 2. Check for text arguments directly after the command
        # Extract everything after /feedspam command, preserving multiline content
        spam_text_argument = message_text.sub(%r{^/feedspam\s*}, "").strip

        Rails.logger.info "feedspam #{spam_text_argument}"
        if spam_text_argument.empty?
          # 3. No text and no reply found: Send a user-friendly prompt with force_reply
          help_message = I18n.t("telegram_bot.feedspam.reply_prompt")

          force_reply_markup = {
            force_reply: true,
            input_field_placeholder: I18n.t("telegram_bot.feedspam.input_field_placeholder"),
            selective: true
          }.to_json # Manual JSON conversion
          bot.api.send_message(
            chat_id: message.chat.id,
            text: help_message,
            parse_mode: "Markdown",
            reply_to_message_id: message.message_id, # Reply to the user's /feedspam command
            reply_markup: force_reply_markup
          )
          return
        else
          # Use the text provided as argument
          execute_spam_training(bot, message, spam_text_argument)
        end
      end
    end
  end


  def execute_spam_training(bot, message, spam_text)
    I18n.with_locale(@lang_code) do
      Rails.logger.info "Spam message to train: #{spam_text}"

      begin
        user_name = [ message.from&.first_name, message.from&.last_name ].compact.join(" ")
        chat_type = message.chat.type

        if chat_type == "private"
          group_name = "Private: " + user_name
        else
          group_name = message.chat.title
        end

        # Save the trained message, which will invoke ActiveModel
        # hook to train the model in the background job
        trained_message = TrainedMessage.create!(
          group_id: message.chat.id,
          group_name: group_name,
          message: spam_text,
          sender_chat_id: message.from.id,
          sender_user_name: user_name,
          message_type: :maybe_spam,
          source: :feedspam_command,
          marked_by: :group_admin
        )

        # Show a preview of what was learned (truncated if too long)
        preview = spam_text.length > 100 ? "#{escape_markdown(spam_text[0..100])}..." : escape_markdown(spam_text)
        response_message = I18n.t("telegram_bot.feedspam.success_message", preview: preview)
        # Send a final confirmation message
        bot.api.send_message(chat_id: message.chat.id, text: response_message, parse_mode: "Markdown")
      rescue => e
        Rails.logger.error "Error in feedspam training: #{e.message}"
        bot.api.send_message(chat_id: message.chat.id, text: "#{I18n.t('telegram_bot.feedspam.failure_message')}")
      end
    end
  end

  def is_admin?(bot, user:, group_id:)
    username = [ user&.first_name, user&.last_name ].compact.join(" ")
    user_id = user.id
    I18n.with_locale(@lang_code) do
      # Check if the user is admin of the target group
      unless is_admin_of_group?(user: user, group_id: group_id)
        bot.api.send_message(
          chat_id: group_id,
          text: I18n.t("telegram_bot.is_admin.error_message", user_name: username, user_id: user_id),
          parse_mode: "Markdown"
        )
        return false
      end
      return true
    end
  end

  def handle_listspam_command(bot, message)
    return unless is_group_chat?(bot, message)
    return unless is_admin?(bot, user: message.from, group_id: message.chat.id)

    # Parse the command: /listspam pageId
    command_parts = message.text.strip.split(/\s+/)

    target_group_id = message.chat.id
    group_title = message.chat.title
    page = command_parts[1].to_i > 0 ? command_parts[1].to_i : 1
    page = 1 if page < 1

    items_per_page = Rails.application.config.items_per_page
    offset = (page - 1) * items_per_page
    buttons = []

    I18n.with_locale(@lang_code) do
      begin
        trained_messages = TrainedMessage.where(group_id: target_group_id, message_type: [ :spam, :maybe_spam ])
                             .order(created_at: :desc)
                             .offset(offset)
                             .limit(items_per_page)

        total_count = TrainedMessage.where(group_id: target_group_id, message_type: [ :spam, :maybe_spam ]).count
        total_pages = (total_count.to_f / items_per_page).ceil

        if trained_messages.empty?
          if page == 1
            bot.api.send_message(
              chat_id: message.chat.id,
              text: "#{I18n.t('telegram_bot.listspam.no_spam_message')}",
              parse_mode: "Markdown"
            )
          else
            bot.api.send_message(
              chat_id: message.chat.id,
              text: I18n.t("telegram_bot.listspam.no_spam_on_page_x_message", group_title: group_title, page: page, target_group_id: target_group_id),
              parse_mode: "Markdown"
            )
          end
        else
          text = "🚫 **#{I18n.t('telegram_bot.listspam.spam_message_text')}** (#{I18n.t('telegram_bot.listspam.page_text')} #{page}/#{total_pages})\n"
          text += "#{I18n.t('telegram_bot.listspam.total_spam_message_text')}: #{total_count}\n\n"

          max_spam_preview_length = Rails.application.config.max_spam_preview_length
          max_spam_preview_button_length = Rails.application.config.max_spam_preview_button_length
          trained_messages.each_with_index do |message, index|
            # Truncate long spam messages for display
            escaped_message = escape_markdown(message.message)
            spam_preview = message.message.length > max_spam_preview_length ? "#{escape_markdown(message.message[0..max_spam_preview_length])}..." : escaped_message
            spam_button_preview = message.message.length > max_spam_preview_button_length ? "#{escape_markdown(message.message[0..max_spam_preview_button_length])}..." : escaped_message
            text += "**#{index + 1}. #{I18n.t('telegram_bot.listspam.user_text')}:** *#{message.sender_user_name}*\n"
            text += "**#{I18n.t('telegram_bot.listspam.message_text')}:** `#{spam_preview}`\n"
            text += "**#{I18n.t('telegram_bot.listspam.spamtype_text')}:** *#{message.training_target}*\n"
            text += "**#{I18n.t('telegram_bot.listspam.banned_text')}:** #{message.created_at.strftime("%Y-%m-%d %H:%M")}\n\n"

            # Create an "mark as ham" button for each user
            callback_data = build_callback_data(CallbackAction::MARK_AS_HAM,
                                                CallbackConstants::TRAINED_MESSAGE_ID => message.id,
                                                CallbackConstants::GROUP_ID=> target_group_id)
            buttons << [ { text: "✅ #{I18n.t('telegram_bot.listspam.mark_as_ham_message')} #{index + 1}. #{spam_button_preview}", callback_data: callback_data } ]
          end

          # Add pagination buttons if needed
          pagination_buttons = []
          if page > 1
            pagination_buttons << { text: I18n.t("telegram_bot.listspam.previous_page"),
                                    callback_data: build_callback_data(CallbackAction::LISTSPAM_PAGE,
                                                                       CallbackConstants::GROUP_ID => target_group_id,
                                                                       CallbackConstants::PAGE => page - 1,
                                                                       CallbackConstants::LANGUAGE => @lang_code) }
          end
          if page < total_pages
            pagination_buttons << { text: I18n.t("telegram_bot.listspam.next_page"),
                                    callback_data: build_callback_data(CallbackAction::LISTSPAM_PAGE,
                                                                       CallbackConstants::GROUP_ID => target_group_id,
                                                                       CallbackConstants::PAGE => page + 1,
                                                                       CallbackConstants::LANGUAGE => @lang_code) }
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
        Rails.logger.error "Error in listspam command: #{e.message} #{buttons}"
        bot.api.send_message(chat_id: message.chat.id, text: "#{I18n.t('telegram_bot.listspam.failure_message')}")
      end
    end
  end

  def handle_listbanuser_command(bot, message)
    return unless is_group_chat?(bot, message)
    return unless is_admin?(bot, user: message.from, group_id: message.chat.id)

    # Parse the command: /listbanuser pageId
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
              text: "#{I18n.t('telegram_bot.listbanuser.no_banned_user_message')}",
              parse_mode: "Markdown"
            )
          else
            bot.api.send_message(
              chat_id: message.chat.id,
              text: I18n.t("telegram_bot.listbanuser.no_banned_on_page_x_message", group_title: group_title, page: page, target_group_id: target_group_id),
              parse_mode: "Markdown"
            )
          end
        else
          text = "🚫 **#{I18n.t("telegram_bot.listbanuser.banned_user_text")}** (#{I18n.t("telegram_bot.listbanuser.page_text")} #{page}/#{total_pages})\n"
          text += "Total banned users: #{total_count}\n\n"
          buttons = []

          max_spam_preview_length = Rails.application.config.max_spam_preview_length
          banned_users.each do |user|
            # Truncate long spam messages for display
            spam_preview = user.spam_message.length > max_spam_preview_length ? "#{escape_markdown(user.spam_message[0..max_spam_preview_length])}..." : escape_markdown(user.spam_message)

            text += "**#{I18n.t("telegram_bot.listbanuser.user_text")}:** *#{user.sender_user_name}*\n"
            text += "**#{I18n.t("telegram_bot.listbanuser.message_text")}:** `#{spam_preview}`\n"
            text += "**#{I18n.t("telegram_bot.listbanuser.banned_text")}:** #{user.created_at.strftime("%Y-%m-%d %H:%M")}\n\n"

            # Create an "unban" button for each user
            callback_data = build_callback_data(CallbackAction::UNBAN, CallbackConstants::USER_ID => user.id, CallbackConstants::GROUP_ID=> target_group_id)
            buttons << [ { text: "✅ #{I18n.t('telegram_bot.listbanuser.unban_message')} #{user.sender_user_name}", callback_data: callback_data } ]
          end

          # Add pagination buttons if needed
          pagination_buttons = []
          if page > 1
            pagination_buttons << { text: I18n.t("telegram_bot.listbanuser.previous_page"),
                                    callback_data: build_callback_data(CallbackAction::LISTBANUSER_PAGE,
                                                                       CallbackConstants::GROUP_ID => target_group_id,
                                                                       CallbackConstants::PAGE => page - 1,
                                                                       CallbackConstants::LANGUAGE => @lang_code) }
          end
          if page < total_pages
            pagination_buttons << { text: I18n.t("telegram_bot.listbanuser.next_page"),
                                    callback_data: build_callback_data(CallbackAction::LISTBANUSER_PAGE,
                                                                       CallbackConstants::GROUP_ID => target_group_id,
                                                                       CallbackConstants::PAGE => page + 1,
                                                                       CallbackConstants::LANGUAGE => @lang_code) }
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
        Rails.logger.error "Error in listbanuser command: #{e.message}"
        bot.api.send_message(chat_id: message.chat.id, text: "#{I18n.t('telegram_bot.listbanuser.unban_message')}")
      end
    end
  end

  def handle_regular_message(bot, message)
    searchable_content = extract_searchable_content(message)
    return if searchable_content.empty?
    Rails.logger.info "Received message: #{searchable_content}"

    group_id = message.chat.id
    group_name = message.chat.title || "private_chat"
    increment_messages_processed(group_id, group_name)

    if is_in_whitelist?(message)
      Rails.logger.info "Skipping inspecting message #{searchable_content} as sender is in whitelist"
      return
    end

    signals = extract_signals(message)

    message_data = {
      message_id: message.message_id,
      text: searchable_content,
      chat_id: message.chat.id,
      chat_type: message.chat.type,
      chat_title: message.chat.title,
      from_id: message.from&.id,
      from_first_name: message.from&.first_name,
      from_last_name: message.from&.last_name,
      date: message.date,
      quote_text: message.quote&.text,
      reply_to_text: message.reply_to_message&.text,
      signals: signals
    }

    SpamAnalysisJob.perform_later(message_data)
    nil
  rescue => e
    Rails.logger.error "Error queuing message #{message.to_h.to_json} for analysis: #{e}\n#{e.backtrace.join("\n")}"
  end

  def is_group_chat?(bot, message)
    I18n.with_locale(@lang_code) do
      # Returns true if the chat type is 'group' or 'supergroup'
      unless is_group_message?(message)
        bot.api.send_message(chat_id: message.chat.id, text: "#{I18n.t('telegram_bot.is_group_chat.error_message')}", parse_mode: "Markdown")
        return false
      end
      return true
    end
  end

  def is_group_message?(message)
    [ "group", "supergroup" ].include?(message.chat.type)
  end

  def is_admin_of_group?(user:, group_id:)
    return false if user.nil?

    # Special case: Channel admins posting via "GroupAnonymousBot"
    return true if user.is_bot && user.username == "GroupAnonymousBot"

    user_id = user.id
    chat_member = TelegramMemberFetcher.get_chat_member(group_id, user_id)
    [ "administrator", "creator" ].include?(chat_member&.status)
  end

  def handle_callback(bot, callback)
    Rails.logger.info "Handling callback #{callback.data}"

    callback_data = parse_callback_data(callback.data)
    action = callback_data[CallbackConstants::ACTION]
    user_id = callback_data[CallbackConstants::USER_ID]
    trained_message_id = callback_data[CallbackConstants::TRAINED_MESSAGE_ID]
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
      when CallbackAction::MARK_AS_HAM
        handle_mark_as_ham_callback(bot, callback, chat_id, message_id, trained_message_id)
      when CallbackAction::LISTSPAM_PAGE
        handle_listspam_pagination_callback(bot, callback, page)
      when CallbackAction::LISTBANUSER_PAGE
        handle_listbanuser_pagination_callback(bot, callback, page)
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

  def handle_mark_as_ham_callback(bot, callback, chat_id, tg_message_id, trained_message_id)
    # Only admin has permission to perform actions
    is_admin = is_admin_of_group?(user: callback.from, group_id: callback.message.chat.id)
    unless is_admin
      # The text is displayed as a small notification pop-up.
      bot.api.answer_callback_query(
        callback_query_id: callback.id,
        text: I18n.t("telegram_bot.is_admin.general_error_message"),
        show_alert: true # Use show_alert: true for a larger, persistent alert box
      )
      return
    end

    I18n.with_locale(@lang_code) do
      trained_message = TrainedMessage.find_by(id: trained_message_id)
      unless trained_message
        return
      end

      begin
        # This will trigger ActiveModel hook to automatically rebuild
        # classifier in a background job
        trained_message.update!(message_type: :ham, marked_by: :group_admin)
        user_name = trained_message.sender_user_name
        user_id = trained_message.sender_chat_id
        edit_message_text(bot, chat_id, tg_message_id, I18n.t("telegram_bot.markasham.success_message", user_name: user_name, user_id: user_id))
      rescue => e
        Rails.logger.error "Error mark message as ham: #{e.message}"
      end
    end
  end

  def handle_unban_callback(bot, callback, chat_id, message_id, banned_user_id)
    # Only admin has permission to perform actions
    is_admin = is_admin_of_group?(user: callback.from, group_id: callback.message.chat.id)
    unless is_admin
      # The text is displayed as a small notification pop-up.
      bot.api.answer_callback_query(
        callback_query_id: callback.id,
        text: I18n.t("telegram_bot.is_admin.general_error_message"),
        show_alert: true # Use show_alert: true for a larger, persistent alert box
      )
      return
    end

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
        messages_to_retrain.update!(message_type: :ham, marked_by: :group_admin)

        begin
          bot.api.unban_chat_member(chat_id: chat_id, user_id: banned_user.sender_chat_id)
        rescue => e
          Rails.logger.error "Failed to unbanning user #{banned_user.sender_chat_id} due to: #{e.message}"
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
    is_admin = is_admin_of_group?(user: callback.from, group_id: callback.message.chat.id)
    unless is_admin
      # The text is displayed as a small notification pop-up.
      bot.api.answer_callback_query(
        callback_query_id: callback.id,
        text: I18n.t("telegram_bot.is_admin.general_error_message"),
        show_alert: true # Use show_alert: true for a larger, persistent alert box
      )
      return
    end

    # Simulate the listbanuser command with the new page
    callback_data = parse_callback_data(callback.data)
    group_id = callback_data[CallbackConstants::GROUP_ID]

    fake_message = Struct.new(:text, :chat, :from).new(
      text: "/listbanuser #{page}",
      chat: callback.message.chat,
      from: callback.from
    )

    # Delete the old message
    bot.api.delete_message(chat_id: callback.message.chat.id, message_id: callback.message.message_id)

    # Send new message with updated page
    handle_listspam_command(bot, fake_message)
  end

  def handle_listbanuser_pagination_callback(bot, callback, page)
    # Only admin has permission to perform actions
    is_admin = is_admin_of_group?(user: callback.from, group_id: callback.message.chat.id)
    unless is_admin
      # The text is displayed as a small notification pop-up.
      bot.api.answer_callback_query(
        callback_query_id: callback.id,
        text: I18n.t("telegram_bot.is_admin.general_error_message"),
        show_alert: true # Use show_alert: true for a larger, persistent alert box
      )
      return
    end

    # Simulate the listbanuser command with the new page
    callback_data = parse_callback_data(callback.data)
    group_id = callback_data[CallbackConstants::GROUP_ID]

    fake_message = Struct.new(:text, :chat, :from).new(
      text: "/listbanuser #{page}",
      chat: callback.message.chat,
      from: callback.from
    )

    # Delete the old message
    bot.api.delete_message(chat_id: callback.message.chat.id, message_id: callback.message.message_id)

    # Send new message with updated page
    handle_listbanuser_command(bot, fake_message)
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

  def is_in_whitelist?(message)
    # 1. don't inspect message from administrator
    return true if is_admin_of_group?(user: message.from, group_id: message.chat.id)

    # 2. Whitelist messages sent on behalf of a channel (channel broadcasts)
    channel_broadcast_blacklist = Rails.application.config.channel_broadcast_blacklist
    if message.sender_chat.present? && !message.sender_chat.id.in?(channel_broadcast_blacklist)
      Rails.logger.info "Skipping inspection for channel message: #{message.to_h.to_json}"
      return true
    end

    # 3. Whitelist replies to the bot's own messages
    # This specifically handles the user replying to the /feedspam prompt.
    replied_to_message = message.reply_to_message
    if replied_to_message && replied_to_message.from&.id == @bot_id
      Rails.logger.info "Skipping inspection for user reply to bot message: #{message.to_h.to_json}"
      return true
    end

    # 4. This prevents the bot's instructional and alert messages from being deleted.
    if message.from&.id == @bot_id
      Rails.logger.info "Skipping spam inspection for a message sent by the bot (ID: #{@bot_id})"
      return true
    end

    false
  end

  # Leveraging signal in feature engineering
  def extract_signals(message)
    signals = []
    if message.external_reply.present?
      signals << SignalTokens::HAS_EXTERNAL_REPLY
      signals << SignalTokens::HAS_PHOTO if message.external_reply.photo.present?
    end
    signals << SignalTokens::HAS_FORWARDED if message.forward_origin.present?
    signals << SignalTokens::HAS_PHOTO if message.photo.present?
    signals << SignalTokens::HAS_QUOTE if message.quote.present?
    signals
  end

  # Escapes special characters for Telegram's Markdown mode
  def escape_markdown(text)
    text.to_s.gsub("\\", "\\\\")
      .gsub("_", '\\_')
      .gsub("*", '\\*')
      .gsub("[", '\\[')
      .gsub("]", '\\]')
      .gsub("(", '\\(')
      .gsub(")", '\\)')
      .gsub("~", '\\~')
      .gsub("`", '\\`')
      .gsub(">", '\\>')
      .gsub("#", '\\#')
      .gsub("+", '\\+')
      .gsub("-", '\\-')
      .gsub("=", '\\=')
      .gsub("|", '\\|')
      .gsub("{", '\\{')
      .gsub("}", '\\}')
      .gsub(".", '\\.')
      .gsub("!", '\\!')
      .gsub("<", '\\<')
  end

  def reply_to_bot?(message)
    replied_to = message.reply_to_message
    replied_to && replied_to.from&.id == @bot_id
  end

  # Extracts all relevant text content from a Telegram message for spam analysis.
  # This includes message text, caption, poll questions, and inline keyboard button text.
  def extract_searchable_content(message)
    content_parts = []
    content_parts << message.text if message.text.present?
    content_parts << message.caption if message.caption.present?
    content_parts << message.poll.question if message.poll&.question.present?
    content_parts << message.sticker.emoji if message.sticker&.emoji.present? # Add sticker emoji
    content_parts << message.quote.text if message.quote.present? && message.quote.text.present?

    if message.reply_markup&.inline_keyboard.present?
      message.reply_markup.inline_keyboard.each do |row|
        row.each do |button|
          content_parts << button.text if button.text.present?
          content_parts << button.url if button.url.present?
        end
      end
    end

    if message&.external_reply.present?
      if message.external_reply&.origin&.sender_user.present?
        content_parts << message.external_reply.origin.sender_user.first_name
        content_parts << message.external_reply.origin.sender_user.last_name
      end

      if message.external_reply&.chat.present?
        content_parts << message.external_reply.chat.title
      end
    end

    content_parts.compact.join(" ").strip
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
