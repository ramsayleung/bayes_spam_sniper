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

    @message_queue = Queue.new
    @processed_hashes = Set.new
    # Load existing message hash into memory
    TrainedMessage.pluck(:message_hash).compact.each { |hash| @processed_hashes.add(hash) }

    # Start background processor thread
    client = TdlibClient.new
    processor_thread = Thread.new { process_message_queue(client) }

    # Set log level
    client.send({ "@type" => "setLogVerbosityLevel", "new_verbosity_level" => 2 })

    begin
      # Main message loop
      state = nil
      loop do
      update = client.receive(1.0)
      next unless update

      case update["@type"]
      when "updateAuthorizationState"
        state = handle_update_authorization_state(update, client)
        break if state == "authorizationStateClosed"
      when "updateNewMessage"
        handle_message_update(update)
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

  def handle_update_authorization_state(update, client)
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
    else
      puts "Unhandled authorization state: #{new_state}"
    end
    new_state
  end

  def handle_message_update(update)
    message = update["message"] || update
    content = message["content"] || update["new_content"]

    return unless content["@type"] == "messageText"

    message_content = content["text"]["text"]
    message_hash = Digest::SHA256.hexdigest(message_content)

    # Fast in-memory duplicate check
    return if @processed_hashes.include?(message_hash)

    # Add to processing queue(non-blocking)
    @message_queue.push({
                          content: message_content,
                          update: update
                        })
  end

  def process_message_queue(client)
    loop do
      begin
        message = @message_queue.pop(timeout: 1.0)
        if message
          update = message[:update]
          handle_update_new_message(update, client)
        end
      rescue ThreadError => e
        puts "ThreadError: #{e}"
      end
    end
  end

  def process_message(message_content, group_id, group_name, user_id, user_name)
    # Process message content
    train_message_if_needed(message_content, :message_content, group_id, group_name, user_id, user_name)
    # Process user name
    train_message_if_needed(user_name, :user_name, group_id, group_name, user_id, user_name)
  end

  def train_message_if_needed(text_to_classify, training_target, group_id, group_name, user_id, user_name)
    text_hash = Digest::SHA256.hexdigest(text_to_classify.to_s)
    existing_message = TrainedMessage.find_by(message_hash: text_hash)

    if existing_message
      puts "Trained message already exists, skipping"
      return
    end

    # Memoize the classifier to avoid creating it twice
    classifier = SpamClassifierService.new(group_id, group_name)
    is_spam, _, _ = classifier.classify(text_to_classify)

    puts "#{training_target} classified result: #{is_spam ? 'maybe_spam' : 'maybe_ham'}"

    spam_count = TrainedMessage.where(message_type: [ :spam, :maybe_spam ], training_target: training_target).count
    ham_count  = TrainedMessage.where(message_type: [ :ham, :maybe_ham ], training_target: training_target).count

    # Logic to balance the dataset
    should_create = (spam_count > ham_count && !is_spam) || (spam_count <= ham_count && is_spam)

    if should_create
      @processed_hashes.add(text_hash)
      TrainedMessage.create!(
        group_id: group_id,
        group_name: group_name,
        message: text_to_classify,
        message_type: is_spam ? :maybe_spam : :maybe_ham,
        sender_user_name: user_name || "Telegram collector",
        training_target: training_target,
        sender_chat_id: user_id
      )
    end
  end

  def handle_update_new_message(update, client)
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
end
