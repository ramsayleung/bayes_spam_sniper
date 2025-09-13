require "ffi"
require "json"

# Minimal TDLib FFI wrapper, tdlib-ruby is conflict with
# telegram-bot-ruby as they depends on dry-core
module TDJson
  if Rails.env.development?
    extend FFI::Library
    lib_name = "tdjson"
    if FFI::Platform.windows?
      ffi_lib File.join(ENV.fetch("TDLIB_PATH"), "#{lib_name}.dll")
    elsif FFI::Platform.mac?
      ffi_lib File.join(ENV.fetch("TDLIB_PATH"), "lib#{lib_name}.dylib")
    else
      ffi_lib File.join(ENV.fetch("TDLIB_PATH"), "lib#{lib_name}.so")
    end

    attach_function :td_json_client_create, [], :pointer
    attach_function :td_json_client_send, [ :pointer, :string ], :void
    attach_function :td_json_client_receive, [ :pointer, :double ], :string
    attach_function :td_json_client_execute, [ :pointer, :string ], :string
    attach_function :td_json_client_destroy, [ :pointer ], :void
  end
end

class TDClient
  def initialize
    @client = TDJson.td_json_client_create
    @request_queue = {}
  end

  def send_async(query, &block)
    request_id = SecureRandom.uuid
    @request_queue[request_id] = block
    query["@extra"] = { request_id: request_id }.to_json
    TDJson.td_json_client_send(@client, JSON.dump(query))
  end

  def receive(timeout = 1.0)
    raw = TDJson.td_json_client_receive(@client, timeout)
    return unless raw

    update = JSON.parse(raw)
    if update["@extra"]
      extra = JSON.parse(update["@extra"])
      if extra["request_id"]
        callback = @request_queue.delete(extra["request_id"])
        callback.call(update) if callback
      end
    end
    update
  end

  def execute(query)
    raw = TDJson.td_json_client_execute(@client, JSON.dump(query))
    raw && JSON.parse(raw)
  end

  def send(query)
    TDJson.td_json_client_send(@client, JSON.dump(query))
  end

  def close
    TDJson.td_json_client_destroy(@client)
  end

  def get_chat(chat_id)
    execute({
              "@type" => "getChat",
              "chat_id" => chat_id
            })
  end

  def get_user(user_id)
    execute({
              "@type" => "getUser",
              "user_id" => user_id
            })
  end
end

namespace :telegram do
  desc "Starts the TDLib client to listen for telegram messages"
  task listen: :environment do
    unless Rails.env.development?
      puts "TDLib client must only run in development env"
      return
    end

    tdlib_path = ENV["TDLIB_PATH"]
    unless tdlib_path && !tdlib_path.empty?
      puts <<~TEXT
        TDLIB_PATH environment variable not found, please build https://github.com/tdlib/td and set it:

        git clone https://github.com/tdlib/td.git
        cd td
        mkdir build && cd build
        cmake -DCMAKE_BUILD_TYPE=Release ..
        cmake --build .
        export TDLIB_PATH=$(pwd)
      TEXT
      puts "TDLIB_PATH not set. Skipping Telegram listener."
      next
    end

    client = TDClient.new

    # Set log level
    client.send({ "@type" => "setLogVerbosityLevel", "new_verbosity_level" => 2 })

    begin
      state = nil
      loop do
      update = client.receive(1.0)
      next unless update

      case update["@type"]
      when "updateAuthorizationState"
        new_state = update["authorization_state"]["@type"]
        puts "Authorization state: #{new_state}"
        state = new_state

        case new_state
        when "authorizationStateWaitTdlibParameters"
          puts "Setting TDLib parameters..."
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
          client.send(params)

        when "authorizationStateWaitPhoneNumber"
          puts "Please enter your phone number (e.g. +15551234567):"
          phone = STDIN.gets.strip
          client.send({
                        "@type" => "setAuthenticationPhoneNumber",
                        "phone_number" => phone
                      })

        when "authorizationStateWaitCode"
          puts "Please enter the code from Telegram/SMS:"
          code = STDIN.gets.strip
          client.send({
                        "@type" => "checkAuthenticationCode",
                        "code" => code
                      })

        when "authorizationStateReady"
          puts "Authorization successful! Listening for messages..."

        when "authorizationStateClosed"
          puts "Authorization closed. Exiting."
          break
        else
          puts "Unhandled authorization state: #{new_state}"
        end
      when "updateNewMessage"
        handleUpdateNewMessage(update, client)
      else
        # ignore other updates
      end
    end

    rescue Interrupt
      puts "\nShutting down..."
    ensure
      client&.close
    end
  end
end

def process_message(message_content, group_id, group_name, user_id, user_name)
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
  if (spam_count > ham_count && !is_spam) || (spam_count <= ham_count && is_spam)
    TrainedMessage.create!(
      group_id: group_id,
      group_name: group_name,
      message: message_content,
      message_type: is_spam ? :maybe_spam : :maybe_ham,
      sender_user_name: user_name || "Telegram collector",
      sender_chat_id: user_id
    )
  end
end

def handleUpdateNewMessage(update, client)
  message = update["message"]
  chat_id = message["chat_id"]
  sender_id = message["sender_id"]["user_id"] rescue nil
  content = message["content"]
  user_name = "Unknown User"
  message_content = content["text"]["text"] if content["@type"] == "messageText"

  # Send asynchronous requests for chat and user data
  client.send_async({ "@type" => "getChat", "chat_id" => chat_id }) do |chat_update|
    chat = chat_update
    group_name = chat["title"] || "Unknown Group"

    if sender_id
      client.send_async({ "@type" => "getUser", "user_id" => sender_id }) do |user_update|
        user = user_update
        user_name = user["first_name"]
        user_name += " " + user["last_name"] if user["last_name"]
        user_name = user["username"] if user["username"]

        unless message_content.blank?
          process_message(message_content, chat_id, group_name, sender_id, user_name)
          puts "Group(#{chat_id}): #{group_name} | User: #{user_name} | Text: #{message_content}"
          puts "----------------------"
        end
      end
    else
      # Handle cases where there's no sender_id (e.g., channel posts)
      unless message_content.blank?
        process_message(message_content, chat_id, group_name, sender_id, user_name)
        puts "Group: #{group_name} | User: #{user_name} | Text: #{message_content}"
        puts "----------------------"
      end
    end
  end
end
