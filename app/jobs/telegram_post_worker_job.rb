class TelegramPostWorkerJob < ApplicationJob
  "background worker to execute job after specific event"
  queue_as :low_priority

  module PostAction
    BAN_USER = "ban_user"
  end

  def perform(args)
    action = args.fetch(:action)
    trained_message = args.fetch(:trained_message)

    case action
    when PostAction::BAN_USER
      ban_user_in_group(trained_message: trained_message)
    end
  end

  private

  def bot
    @bot ||= Rails.application.config.telegram_bot
  end

  def ban_user_in_group(trained_message:)
    user_name = trained_message.sender_user_name
    user_id = trained_message.sender_chat_id
    group_id = trained_message.group_id
    I18n.with_locale("en") do
      bot.api.ban_chat_member(chat_id: trained_message.group_id, user_id: trained_message.sender_chat_id)
      BannedUser.find_or_create_by!(
        group_id: group_id,
        sender_chat_id: user_id
      ) do |banned_user|
        banned_user.group_name = trained_message.group_name
        banned_user.sender_user_name = user_name
        banned_user.spam_message = trained_message.message
        banned_user.message_id = trained_message.message_id
      end
      bot.api.send_message(
        chat_id: group_id,
        text: I18n.t("telegram_bot.handle_regular_message.ban_user_message", user_name: user_name, user_id: user_id),
        parse_mode: "Markdown"
      )
    end
  end
end
