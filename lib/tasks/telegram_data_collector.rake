require "tdlib-ruby"

namespace :telegram do
  desc "Starts the TDLib client to listen for telegram message to automatically collect spam or ham data"
  task listen: :environment do
    unless Rails.env.development?
      puts "TDLib client must only run in development env"
      return
    end

    unless ENV.include?("TDLIB_PATH")
      help_message = <<~TEXT
TDLIB_PATH environment variable not found, please build https://github.com/tdlib/td and set environment variable
git clone git@github.com:tdlib/td.git
cd td
mkdir build
cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
cmake --build .
export TDLIB_PATH=$(pwd)
      TEXT
      puts help_message
      return
    end

    TD.configure do |config|
      config.lib_path = ENV.fetch("TDLIB_PATH")
    end

    TD::Api.set_log_verbosity_level(2)
    client = TD::Client.new

    begin
      state = nil
      mutex = Mutex.new
      cond = ConditionVariable.new

      # Authorization state handler
      client.on("updateAuthorizationState") do |update|
      new_state = update.dig("authorization_state", "@type")
      puts "Authorization state: #{new_state}"

      mutex.synchronize do
        state = new_state
        cond.signal
      end
    end

      # Message Handlers
      client.on("updateNewMessage") do |update|
      puts "\nNEW MESSAGE RECEIVED"
      message = update["message"]
      chat_id = message["chat_id"]
      content = message["content"]

      if content["@type"] == "messageText"
        message_content = content["text"]["text"]
        process_message(message_content)
        puts "Chat ID: #{chat_id} | Text: #{message_content}\n"
      else
        puts "Chat ID: #{chat_id} | Type: #{content['@type']}\n"
      end
      puts "----------------------\n"
    end

      client.on("updateMessageContent") do |update|
      puts "MESSAGE EDITED\n"
      chat_id = update["chat_id"]
      new_content = update["new_content"]

      if new_content["@type"] == "messageText"
        message_content = new_content["text"]["text"]
        process_message(message_content)
        puts "Chat ID: #{chat_id} | New Text: #{}\n"
      else
        puts "Chat ID: #{chat_id} | New Type: #{new_content['@type']}\n"
      end
      puts "----------------------\n"
    end

      # Authorization Loop
      # https://core.telegram.org/tdlib/getting-started#user-authorization
      current_state = nil
      mutex.synchronize do
      loop do
        # Wait for state change
        cond.wait(mutex) while state == current_state
        current_state = state
        puts "Processing state: #{current_state}"

        case current_state
        when "authorizationStateWaitTdlibParameters"
          puts "Setting TDLib parameters..."
          mutex.unlock  # Release before network call

          params = {
            "@type" => "setTdlibParameters",
            "api_id" => Rails.application.credentials.dig(:tdlib_app_id),
            "api_hash" => Rails.application.credentials.dig(:tdlib_app_hash_id),
            "database_directory" => "./tdlib-db",
            "files_directory" => "./tdlib-files",
            "use_file_database" => true,
            "use_chat_info_database" => true,
            "use_message_database" => true,
            "use_secret_chats" => true,
            "system_language_code" => "en",
            "device_model" => "Ruby TD Client",
            "application_version" => "1.0"
          }
          client.broadcast_and_receive(params)
          mutex.lock  # Re-acquire after network call

        when "authorizationStateWaitPhoneNumber"
          puts "Please, enter your phone number (e.g., +15551234567):"
          mutex.unlock  # Release before blocking input
          phone = STDIN.gets.strip

          params = {
            "@type" => "setAuthenticationPhoneNumber",
            "phone_number" => phone
          }
          client.broadcast_and_receive(params)
          mutex.lock  # Re-acquire

        when "authorizationStateWaitCode"
          puts "Please, enter code from Telegram/SMS:"
          mutex.unlock  # Release before blocking input
          code = STDIN.gets.strip

          params = {
            "@type" => "checkAuthenticationCode",
            "code" => code
          }
          client.broadcast_and_receive(params)
          mutex.lock  # Re-acquire

        when "authorizationStateReady"
          puts "Authorization successful! Listening for messages..."
          # Wait for potential state changes (disconnections, etc.)
          cond.wait(mutex)

        when "authorizationStateClosed"
          puts "Authorization closed. Exiting."
          break

        else
          puts "Unhandled authorization state: #{current_state}"
        end
      end
    end

    rescue Interrupt
      puts "\nShutting down..."
    ensure
      client&.close
    end
  end
end

def process_message(message_content)
  group_id = GroupClassifierState::TELEGRAM_DATA_COLLECTOR_GROUP_ID
  group_name = GroupClassifierState::TELEGRAM_DATA_COLLECTOR_GROUP_NAME
  classifier = SpamClassifierService.new(group_id, group_name)
  message_hash = Digest::SHA256.hexdigest(message_content.to_s)
  existing_message = TrainedMessage.find_by(message_hash: message_hash)
  if existing_message
    puts "Message already exists, skipping"
    return
  end

  spam_count = TrainedMessage.where(message_type: [ :spam, :maybe_spam ]).count
  ham_count = TrainedMessage.where(message_type: [ :ham, :maybe_ham ]).count

  # Having reasonably balanced datasets is generally beneficial for
  # reduces bias and improves accuracy
  is_spam, spam_score, ham_score = classifier.classify(message_content)
  puts "classified result: #{is_spam ? "maybe_spam": "maybe_ham"}"
  if spam_count > ham_count
    # only interested in ham
    if !is_spam
      TrainedMessage.create!(
        group_id: group_id,
        group_name: group_name,
        message: message_content,
        message_type: :maybe_ham,
        sender_chat_id: 0,
        sender_user_name: "Telegram collector"
      )
    end

  else
    # interested in spam
    if is_spam
      TrainedMessage.create!(
        group_id: group_id,
        group_name: group_name,
        message: message_content,
        message_type: :maybe_spam,
        sender_chat_id: 0,
        sender_user_name: "Telegram collector"
      )
    end
  end
end
