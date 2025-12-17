require "ostruct"
require "telegram/bot"

class SpamAnalysisJob < ApplicationJob
  include PrometheusMetrics
  queue_as :spam_analysis

  def bot
    @bot ||= Telegram::Bot::Client.new(Rails.application.credentials.dig(:telegram_bot_token))
  end

  def perform(message_data)
    message = reconstruct_message(message_data)

    Rails.logger.info "Analyzing message asynchronously: #{message.text}"
    return if message.text.nil? || message.text.strip.empty?

    start_time = Time.current
    is_spam = false

    # Check if the main message is spam
    spam_detection_service = SpamDetectionService.new(message)
    result = spam_detection_service.process

    if result.is_spam
      is_spam = true
      Rails.logger.info "Message flagged as spam due to message itself is spam"
      process_spam_message(message)
    elsif message.quote_text # Check if quoting a spam message (especially from channels)
      quoted_text = message.quote_text

      if quoted_text
        original_message = message
        quoted_message = OpenStruct.new(
          message_id: original_message.message_id,
          from: original_message.from,
          date: original_message.date,
          chat: original_message.chat,
          text: quoted_text,
          signals: original_message.signals
        )
        replied_spam_service = SpamDetectionService.new(quoted_message)
        replied_result = replied_spam_service.process

        if replied_result.is_spam
          is_spam = true
          Rails.logger.info "Message flagged as spam due to quoting spam content"
          process_spam_message(message)
        end
      end
    end

    processing_time = Time.current - start_time
    increment_message_processing_time(processing_time, message.chat.id, message.chat.title || "private_chat")
    Rails.logger.info "Asynchronous spam analysis completed in #{processing_time}s for group #{message.chat.id}"
  rescue => e
    Rails.logger.error "Error in async spam analysis: #{e.message}\n#{e.backtrace.join("\n")}"
  end

  private

  def reconstruct_message(message_data)
    message_data = message_data.with_indifferent_access
    OpenStruct.new(
      message_id: message_data[:message_id],
      text: message_data[:text],
      chat: OpenStruct.new(
        id: message_data[:chat_id],
        type: message_data[:chat_type],
        title: message_data[:chat_title]
      ),
      from: OpenStruct.new(
        id: message_data[:from_id],
        first_name: message_data[:from_first_name],
        last_name: message_data[:from_last_name]
      ),
      date: message_data[:date],
      quote_text: message_data[:quote_text],
      reply_to_message: message_data[:reply_to_text] ? OpenStruct.new(text: message_data[:reply_to_text]) : nil,
      signals: message_data[:signals] || []
    )
  end

  def process_spam_message(message)
    increment_spam_detected(message.chat.id, message.chat.title || "private_chat")

    # Delete the original spam message
    begin
      bot.api.delete_message(chat_id: message.chat.id, message_id: message.message_id)
    rescue Telegram::Bot::Exceptions::ResponseError => e
      if e.description.include?("message to delete not found")
        Rails.logger.info "Spam message already deleted: #{e.message}"
      else
        Rails.logger.error "Error deleting spam message: #{e.message}"
      end
    end

    # Send the warning message
    username = [ message.from&.first_name, message.from&.last_name ].compact.join(" ")
    delete_message_delay = Rails.application.config.delete_message_delay
    alert_msg = I18n.t("telegram_bot.handle_regular_message.alert_message",
                       user_name: username,
                       user_id: message.from.id,
                       delete_message_delay: delete_message_delay)
    sent_warning_message = bot.api.send_message(
      chat_id: message.chat.id,
      text: alert_msg,
      parse_mode: "Markdown"
    )

    # Schedule deletion of the warning message
    TelegramBackgroundWorkerJob.set(wait: delete_message_delay.minutes).perform_later(
      action: PostAction::DELETE_ALERT_MESSAGE,
      chat_id: sent_warning_message.chat.id,
      message_id: sent_warning_message.message_id
    )
  end
end
