require "jieba_rb"

class SpamClassifierService
  # A spam message classifier based on Naive Bayes Theorem

  attr_reader :group_id, :classifier_state, :group_name

  def initialize(group_id, group_name)
    @group_id = group_id
    @group_name = group_name
    @classifier_state = GroupClassifierState.find_or_create_by!(group_id: @group_id) do |new_state|
      # Find the most recently updated classifier for group to use as a template.
      template = GroupClassifierState.for_group.order(updated_at: :desc).first
      if template
        new_state.spam_counts         = template.spam_counts.dup
        new_state.ham_counts          = template.ham_counts.dup
        new_state.total_spam_words    = template.total_spam_words
        new_state.total_ham_words     = template.total_ham_words
        new_state.total_spam_messages = template.total_spam_messages
        new_state.total_ham_messages  = template.total_ham_messages
        new_state.vocabulary_size     = template.vocabulary_size
      else
        # If no template exists, initialize an empty state.
        new_state.spam_counts         = {}
        new_state.ham_counts          = {}
        new_state.total_spam_words    = 0
        new_state.total_ham_words     = 0
        new_state.total_spam_messages = 0
        new_state.total_ham_messages  = 0
        new_state.vocabulary_size     = 0
      end

      new_state.group_name = group_name
    end
  end

  def train_only(trained_message)
    tokens = tokenize(trained_message.message)
    vocabulary = Set.new((@classifier_state.spam_counts.keys + @classifier_state.ham_counts.keys))
    if trained_message.spam?
      @classifier_state.total_spam_messages += 1
      @classifier_state.total_spam_words += tokens.size
      tokens.each do |token|
        @classifier_state.spam_counts[token] = @classifier_state.spam_counts.fetch(token, 0) + 1
        vocabulary.add(token)
      end
    else # :ham
      @classifier_state.total_ham_messages += 1
      @classifier_state.total_ham_words += tokens.size
      tokens.each do |token|
        @classifier_state.ham_counts[token] = @classifier_state.ham_counts.fetch(token, 0) + 1
        vocabulary.add(token)
      end
    end

    @classifier_state.vocabulary_size = vocabulary.size
  end

  def train(trained_message)
    train_only(trained_message)
    @classifier_state.save!
  end

  def train_batch(trained_messages)
    trained_messages.each do |trained_message|
      train_only(trained_message)
    end
    @classifier_state.save!
  end

  def classify(message_text)
    # P(Spam|Words) = P(Words|Spam) * P(Spam) / P(Words)
    # Return false if the model isn't trained enough
    @classifier_state.reload
    return [ false, 0.0, 0.0 ] if @classifier_state.total_ham_messages == 0 || @classifier_state.total_spam_messages == 0

    tokens = tokenize(message_text)
    total_messages = @classifier_state.total_spam_messages + @classifier_state.total_ham_messages

    # Calculate prior probabilities in log space
    # Use Math.log to resolve numerical underflow problem
    prob_spam_prior = Math.log(@classifier_state.total_spam_messages.to_f / total_messages)
    prob_ham_prior = Math.log(@classifier_state.total_ham_messages.to_f / total_messages)

    spam_score = prob_spam_prior
    ham_score = prob_ham_prior

    vocab_size = @classifier_state.vocabulary_size

    tokens.each do |token|
      # Add 1 for Laplace smoothing, Laplace smoothing is tailored to solve zero probability problem
      spam_count = @classifier_state.spam_counts.fetch(token, 0) + 1
      spam_score += Math.log(spam_count.to_f / (@classifier_state.total_spam_words + vocab_size))

      ham_count = @classifier_state.ham_counts.fetch(token, 0) + 1
      ham_score += Math.log(ham_count.to_f / (@classifier_state.total_ham_words + vocab_size))
    end

    diff = spam_score - ham_score
    # stable logistic conversion
    p_spam = if diff.abs > 700
               diff > 0 ? 1.0 : 0.0
    else
               1.0 / (1.0 + Math.exp(-diff))
    end

    confidence_threshold = Rails.application.config.probability_threshold
    is_spam = p_spam >= confidence_threshold
    [ is_spam, spam_score, ham_score ]
  end

  class << self
    def rebuild_for_group(group_id, group_name)
      service = new(group_id, group_name)
      service.rebuild_classifier
    end
  end

  def rebuild_classifier
    Rails.logger.info "Rebuild classifier for group_id: #{group_id}"
    messages_to_train = if group_id == GroupClassifierState::USER_NAME_CLASSIFIER_GROUP_ID
                          TrainedMessage.trainable.for_user_name
    else
                          TrainedMessage.trainable.for_message_content
    end

    ActiveRecord::Base.transaction do
      classifier_state.update!(
        group_name: group_name,
        spam_counts: {},
        ham_counts: {},
        total_spam_words: 0,
        total_ham_words: 0,
        total_spam_messages: 0,
        total_ham_messages: 0,
        vocabulary_size: 0
      )

      # Retrain from all trainable messages
      messages_to_train.find_each do |message|
        train_only(message)
      end
      classifier_state.save!
    end
  end

  def tokenize(text)
    cleaned_text = clean_text(text)
    # This regex pre-tokenizes the string into 4 groups:
    # 1. Emojis (one or more)
    # 2. Chinese characters (one or more)
    # 3. English words/numbers (one or more)
    # 4. Punctuation/Symbols that we might want to discard later
    pre_tokens = cleaned_text.scan(/(\p{Emoji_Presentation}+)|(\p{Han}+)|([a-zA-Z0-9]+)|([[:punct:]。、，！？]+)/).flatten.compact

    processed_tokens = pre_tokens.flat_map do |token|
      if token.match?(/\p{Emoji_Presentation}/)
        # Split sequences of emojis into individual characters
        # 🚘🚘🚘 => "🚘", "🚘", "🚘"
        token.chars
      elsif token.match?(/\p{Han}/)
        # Only send pure Chinese text to Jieba for segmentation
        JIEBA.cut(token)
      else
        token
      end
    end

    processed_tokens = processed_tokens
                         .reject(&:blank?)                    # Remove empty strings
                         .reject { |token| pure_punctuation?(token) } # Remove pure punctuation
                         .reject { |token| pure_numbers?(token) }     # Remove pure numbers
                         .map(&:downcase)                     # Normalize case (for mixed content)

    processed_tokens
  end

  def clean_text(text)
    return "" if text.nil?

    cleaned = text.to_s.strip

    # Step 1: Handle anti-spam separators
    # This still handles the cases like "合-约" -> "合约"
    previous = ""
    while previous != cleaned
      previous = cleaned.dup
      cleaned = cleaned.gsub(/([一-龯A-Za-z0-9])[^一-龯A-Za-z0-9\s]+([一-龯A-Za-z0-9])/, '\1\2')
    end

    # Step 2: Handle anti-spam SPACES between Chinese characters
    # This specifically targets the "想 赚 钱" -> "想赚钱" case.
    # We run it in a loop to handle multiple spaces, e.g., "社 区" -> "社区"
    previous = ""
    while previous != cleaned
      previous = cleaned.dup
      # Find a Chinese char, followed by one or more spaces, then another Chinese char
      cleaned = cleaned.gsub(/([一-龯])(\s+)([一-龯])/, '\1\3')
    end

    # Step 3: Add strategic spaces
    # This helps jieba segment properly, e.g., "社区ETH" -> "社区 ETH"
    cleaned = cleaned.gsub(/([一-龯])([A-Za-z0-9])/, '\1 \2')
    cleaned = cleaned.gsub(/([A-Za-z0-9])([一-龯])/, '\1 \2')

    # Step 4: Remove excessive space
    cleaned = cleaned.gsub(/\s+/, " ").strip

    cleaned
  end

  def pure_punctuation?(token)
    # Check if token contains only punctuation marks
    token.match?(/^[[:punct:]。、，！？；：""''（）【】《》〈〉「」『』…—–]+$/)
  end

  def pure_numbers?(token)
    # Check if token contains only numbers (Arabic or Chinese)
    token.match?(/^[0-9一二三四五六七八九十百千万亿零]+$/)
  end
end
