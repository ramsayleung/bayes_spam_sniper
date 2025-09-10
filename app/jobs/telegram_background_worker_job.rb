module PostAction
  BAN_USER = "ban_user"
  # Automatically delete alert message to avoid polluting the group chat
  DELETE_ALERT_MESSAGE = "delete_alert_msg"
end

class TelegramBackgroundWorkerJob < ApplicationJob
  "background worker to execute job after specific event"
  queue_as :low_priority

  def perform(args)
    action = args.fetch(:action)

    case action
    when PostAction::BAN_USER
      trained_message = args.fetch(:trained_message)
      ban_user_in_group(trained_message: trained_message)
    when PostAction::DELETE_ALERT_MESSAGE
      chat_id = args.fetch(:chat_id)
      message_id = args.fetch(:message_id)
      delete_message(chat_id: chat_id, message_id: message_id)
    end
  end

  private

  def bot
    @bot ||= Rails.application.config.telegram_bot
  end

  def delete_message(chat_id:, message_id:)
    Rails.logger.info "Deleting message for chat_id: #{chat_id}, message_id: #{message_id}"
    begin
      bot.api.delete_message(chat_id: chat_id, message_id: message_id)
    rescue Telegram::Bot::Exceptions::ResponseError => e
      Rails.logger.warn "Faile to delete alert message #{e} #{message_id} in chat #{chat_id}"
    end
  end

  def ban_user_in_group(trained_message:)
    user_name = trained_message.sender_user_name
    user_id = trained_message.sender_chat_id
    group_id = trained_message.group_id
    if group_id in [ TELEGRAM_DATA_COLLECTOR_GROUP_ID, USER_NAME_CLASSIFIER_GROUP_ID ]
      Rails.logger.info "Skip banning user in data imported group"
      return
    end

    if user_id in [ 0 ]
      Rails.logger.info "Skip banning user for import trained data set"
      return
    end

    begin
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
    rescue Telegram::Bot::Exceptions::ResponseError => e
      Rails.logger.error "Faile to ban user in a group #{e} #{user_id}:#{user_name} in chat #{group_id}"
    end
  end
end
