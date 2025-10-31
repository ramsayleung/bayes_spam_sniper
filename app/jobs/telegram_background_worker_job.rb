module PostAction
  BAN_USER = "ban_user"
  # Automatically delete alert message to avoid polluting the group chat
  DELETE_ALERT_MESSAGE = "delete_alert_msg"
  # Ban user across all groups
  GLOBAL_BAN_USER = "global_ban_user"
end

class TelegramBackgroundWorkerJob < ApplicationJob
  "background worker to execute job after specific event"
  queue_as :low_priority

  def perform(args)
    Rails.logger.info "Performing telegram background job: #{args}"
    action = args.fetch(:action)

    case action
    when PostAction::BAN_USER
      trained_message_data = args.fetch(:trained_message_data)
      groups = [ { id: trained_message_data[:group_id], name: trained_message_data[:group_name] } ]
      ban_user_in_groups(trained_message_data: trained_message_data, groups: groups)

    when PostAction::GLOBAL_BAN_USER
      trained_message_data = args.fetch(:trained_message_data)
      group_ids = GroupClassifierState.distinct.pluck(:group_id)
      groups = GroupClassifierState.distinct.pluck(:group_id, :group_name).map { |id, name| { id: id, name: name } }
      source_groups = [ { id: trained_message_data[:group_id], name: trained_message_data[:group_name] } ]
      all_groups = groups + source_groups
      ban_user_in_groups(trained_message_data: trained_message_data, groups: all_groups)
    when PostAction::DELETE_ALERT_MESSAGE
      chat_id = args.fetch(:chat_id)
      message_id = args.fetch(:message_id)
      delete_message(chat_id: chat_id, message_id: message_id)
    end
  end

  private

  def bot
    @bot ||= Telegram::Bot::Client.new(Rails.application.credentials.dig(:telegram_bot_token))
  end

  def delete_message(chat_id:, message_id:)
    chat_member = TelegramMemberFetcher.get_bot_chat_member(chat_id)
    can_delete_messages = [ "administrator", "creator" ].include?(chat_member&.status) && chat_member&.can_delete_messages
    unless can_delete_messages
      Rails.logger.info "Skip deleting message due to insufficient permission of group: #{chat_id}"
      return
    end

    Rails.logger.info "Deleting message for chat_id: #{chat_id}, message_id: #{message_id}"
    begin
      bot.api.delete_message(chat_id: chat_id, message_id: message_id)
    rescue Telegram::Bot::Exceptions::ResponseError => e
      Rails.logger.warn "Faile to delete alert message #{e} #{message_id} in chat #{chat_id}"
    end
  end

  def ban_user_in_groups(trained_message_data:, groups:)
    user_id = trained_message_data[:sender_chat_id]
    user_name = trained_message_data[:sender_user_name]
    Rails.logger.info "Banning user #{user_id} #{user_name} in groups: #{groups}"
    groups.each do |group|
      group_id = group[:id]
      group_name = group[:name]

      chat_member = TelegramMemberFetcher.get_bot_chat_member(group_id)
      can_ban_user = [ "administrator", "creator" ].include?(chat_member&.status) && chat_member&.can_restrict_members
      unless can_ban_user
        Rails.logger.info "Skip banning user due to insufficient permission of group: #{group_id}"
        next
      end

      if group_id.in?([ GroupClassifierState::TELEGRAM_DATA_COLLECTOR_GROUP_ID, GroupClassifierState::USER_NAME_CLASSIFIER_GROUP_ID ])
        Rails.logger.info "Skip banning user in data imported group"
        next
      end

      if user_id == 0
        Rails.logger.info "Skip banning user for import trained data set"
        next
      end

      begin
        bot.api.ban_chat_member(chat_id: group_id, user_id: user_id)

        Rails.logger.info "user #{user_id} #{user_name} has been ban in group #{group_id}: #{group_name}"
        BannedUser.find_or_create_by!(
          group_id: group_id,
          sender_chat_id: user_id
        ) do |banned_user|
        banned_user.group_name = group_name
        banned_user.sender_user_name = user_name
        banned_user.spam_message = trained_message_data[:message]
        banned_user.message_id = trained_message_data[:message_id]
      end

        I18n.with_locale("en") do
        i18ntext = groups.length <= 1 ? "telegram_bot.handle_regular_message.ban_user_message" : "telegram_bot.handle_regular_message.global_ban_user_message"
        bot.api.send_message(
          chat_id: group_id,
          text: I18n.t(i18ntext, user_name: user_name, user_id: user_id),
          parse_mode: "Markdown"
        )
      end
      rescue Telegram::Bot::Exceptions::ResponseError => e
        Rails.logger.error "Faile to ban user #{user_id}:#{user_name} in Telegram group #{group_id} #{group_name} #{e}"
      end
    end
  end
end
