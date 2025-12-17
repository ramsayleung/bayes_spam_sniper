class SpamDetectionService
  def initialize(tg_message_struct)
    @tg_message_struct = tg_message_struct
    @group_id = tg_message_struct.chat&.id
    @group_name = tg_message_struct.chat&.title
    @user_id = tg_message_struct.from&.id
    @username = [ tg_message_struct.from&.first_name, tg_message_struct.from&.last_name ].compact.join(" ")

    raw_message_text = TextCleaner.extract_found_message(tg_message_struct.text)
    signals = tg_message_struct.signals || []
    if signals.any?
      @message_text = raw_message_text + " " + signals.join(" ")
    else
      @message_text = raw_message_text
    end
    @is_confident = false
  end

  def process
    return non_spam_result unless valid_message?

    rule_result = RuleBasedClassifier.new(@message_text).classify
    if rule_result.is_spam
      message_type = @is_confident ? :spam : :maybe_spam
      create_trained_message(@message_text, rule_result.target, message_type)
      return rule_result
    end

    targets_to_check = [
      { name: "message_content", value: @message_text },
      { name: "user_name",       value: @username }
    ]

    targets_to_check.each do |target_info|
      result = check_target(target_info[:name], target_info[:value])

      if result.is_spam
        # If any target is found to be spam, we create the record and stop immediately.
        message_type = @is_confident ? :spam : :maybe_spam
        create_trained_message(target_info[:value], target_info[:name], message_type)
        return result
      else
        # collect ham data if spam message is more than ham message to balance the dataset
        spam_count, ham_count = SpamDetectionService.get_message_count_by_target(target_info[:name])
        # highly confident it's a ham
        if spam_count > ham_count && result.p_spam < 0.1
          create_trained_message(target_info[:value], target_info[:name], :maybe_ham)
        end
      end
    end

    # If the loop completes without finding spam, the message is clean.
    non_spam_result
  end

  private

  def self.get_message_count_by_target(target)
    spam_count = TrainedMessage.where(message_type: [ :spam, :maybe_spam ], training_target: target).count
    ham_count  = TrainedMessage.where(message_type: [ :ham, :maybe_ham ], training_target: target).count
    [ spam_count, ham_count ]
  end

  def check_target(target_name, target_value)
    content_hash = Digest::SHA256.hexdigest(target_value.to_s)
    existing_message = TrainedMessage.find_by(message_hash: content_hash)

    if existing_message
      result = handle_existing_message(existing_message)
      # If we got a definitive result (spam or ham), return it immediately.
      # If the result was nil (from 'untrained'), we'll fall through to the classifier.
      return result if result
    end

    # Fallback to the Bayesian classifier if no existing message was found
    # OR if the existing message was 'untrained'.
    classify_with_bayesian(target_name, target_value)
  end

  def handle_existing_message(existing_message)
    case existing_message.message_type
    when "spam"
      @is_confident = true
      Rails.logger.info "Same message exists and already marked as spam: #{existing_message.message}, training target: #{existing_message.training_target}"
      Shared::ClassificationResult.new(is_spam: true, target: existing_message.training_target, p_spam: 1)
    when "ham"
      Rails.logger.info "Same message exists and already marked as ham: #{existing_message.message}, training target: #{existing_message.training_target}"
      non_spam_result
    when "untrained"
      # Signal that this is not a definitive result
      nil
    end
  end


  def classify_with_bayesian(target_name, target_value)
    classifier = build_classifier(target_name)
    is_spam, p_spam = classifier.classify(target_value)

    Rails.logger.info "Classified '#{target_value}' against '#{target_name}': is_spam=#{is_spam}, p_spam=#{p_spam}"
    Shared::ClassificationResult.new(is_spam: is_spam, target: target_name, p_spam: p_spam)
  end

  def build_classifier(target_name)
    case target_name
    when "user_name"
      SpamClassifierService.new(
        GroupClassifierState::USER_NAME_CLASSIFIER_GROUP_ID,
        GroupClassifierState::USER_NAME_CLASSIFIER_GROUP_NAME
      )
    when "message_content"
      SpamClassifierService.new(@group_id, @group_name)
    end
  end

  def create_trained_message(content, target, message_type)
    message_hash = Digest::SHA256.hexdigest(content.to_s)
    marked_by = message_type.in?([ :ham, :spam ]) ? :auto_sync : :not_marked_yet
    TrainedMessage.create(
      message_hash: message_hash,
      group_id: @group_id,
      group_name: @group_name,
      message: content,
      training_target: target,
      sender_chat_id: @user_id,
      sender_user_name: @username,
      message_type: message_type,
      message_id: @tg_message_struct.message_id,
      marked_by: marked_by
    )
  end

  def valid_message?
    !@message_text.to_s.strip.empty?
  end

  def non_spam_result
    Shared::ClassificationResult.new(is_spam: false, target: nil, p_spam: 0)
  end
end
