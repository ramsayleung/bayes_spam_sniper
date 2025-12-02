require "jieba_rb"

class SpamClassifierService
  # A spam message classifier based on Naive Bayes Theorem

  attr_reader :group_id, :classifier_state, :group_name

  def initialize(group_id, group_name, classifier_state: nil)
    @group_id = group_id
    @group_name = group_name
    @classifier_state = classifier_state || GroupClassifierState.find_or_create_by!(group_id: @group_id) do |new_state|
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
    # Lazily initialize the vocabulary set ONCE per service instance
    @vocabulary ||= Set.new((@classifier_state.spam_counts.keys + @classifier_state.ham_counts.keys))

    tokens = tokenize(trained_message.message)

    if trained_message.spam?
      @classifier_state.total_spam_messages = (@classifier_state.total_spam_messages || 0).to_i + 1
      @classifier_state.total_spam_words = (@classifier_state.total_spam_words || 0).to_i + tokens.size
      tokens.each do |token|
        @classifier_state.spam_counts[token] = @classifier_state.spam_counts.fetch(token, 0) + 1
        @vocabulary.add(token)
      end
    else # :ham - FALSE POSITIVE BIAS: count ham tokens double
      # https://www.paulgraham.com/better.html
      @classifier_state.total_ham_messages = (@classifier_state.total_ham_messages || 0).to_i + 1
      @classifier_state.total_ham_words = (@classifier_state.total_ham_words || 0).to_i + (tokens.size * 2) # Double
      # count for bias
      tokens.each do |token|
        @classifier_state.ham_counts[token] = @classifier_state.ham_counts.fetch(token, 0) + 2 # Double weight
        @vocabulary.add(token)
      end
    end

    @classifier_state.vocabulary_size = @vocabulary.size
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
    @classifier_state.reload

    # Check if either value is nil or zero
    return [ false, 0.0 ] if @classifier_state.total_ham_messages.nil? || @classifier_state.total_ham_messages&.zero? ||
                           @classifier_state.total_spam_messages.nil? || @classifier_state.total_spam_messages&.zero?

    # Ensure both values are numeric before proceeding
    total_spam = @classifier_state.total_spam_messages.to_i
    total_ham = @classifier_state.total_ham_messages.to_i

    total_messages = total_spam + total_ham
    return [ false, 0.0 ] if total_messages.zero?

    # These are the actual priors
    prob_spam_prior = total_spam.to_f / total_messages
    prob_ham_prior = total_ham.to_f / total_messages

    tokens = tokenize(message_text)

    # Pass the priors to the selection method for consistent logic
    significant_tokens = get_significant_tokens(tokens, prob_spam_prior, prob_ham_prior)

    # Start scores with the log of the priors
    spam_score = Math.log(prob_spam_prior)
    ham_score = Math.log(prob_ham_prior)

    significant_tokens.each do |token|
      spam_likelihood, ham_likelihood = get_likelihoods(token)

      spam_score += Math.log(spam_likelihood)
      ham_score += Math.log(ham_likelihood)
    end

    diff = spam_score - ham_score
    p_spam = 1.0 / (1.0 + Math.exp(-diff))

    confidence_threshold = Rails.application.config.probability_threshold
    is_spam = p_spam >= confidence_threshold

    Rails.logger.info "classified_result: #{is_spam ? "maybe_spam": "maybe_ham"}, p_spam: #{p_spam.round(4)}, tokens: #{significant_tokens.join(', ')}"

    [ is_spam, p_spam ]
  end


  def tokenize(text)
    cleaned_text = TextCleaner.call(text)
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

  def pure_punctuation?(token)
    # Check if token contains only punctuation marks
    token.match?(/^[[:punct:]。、，！？；：""''（）【】《》〈〉「」『』…—–]+$/)
  end

  def pure_numbers?(token)
    # Check if token contains only numbers (Arabic or Chinese)
    token.match?(/^[0-9一二三四五六七八九十百千万亿零]+$/)
  end

  # It correctly calculates P(token|class) for all cases using Laplace smoothing.
  def get_likelihoods(token)
    vocab_size = @classifier_state.vocabulary_size.to_i

    # For a spam-only word, ham_count is 0, so ham_likelihood will be very small.
    # This is the correct, mathematically consistent way to handle it.
    spam_count = @classifier_state.spam_counts.fetch(token, 0)
    total_spam_words = @classifier_state.total_spam_words.to_i
    spam_likelihood = (spam_count + 1.0) / (total_spam_words + vocab_size)

    ham_count = @classifier_state.ham_counts.fetch(token, 0)
    total_ham_words = @classifier_state.total_ham_words.to_i
    ham_likelihood = (ham_count + 1.0) / (total_ham_words + vocab_size)

    [ spam_likelihood, ham_likelihood ]
  end

  # Corrected to use the actual priors when determining "interestingness"
  def get_significant_tokens(tokens, prob_spam_prior, prob_ham_prior)
    # Use a Set to consider each unique token only once
    unique_tokens = tokens.to_set

    token_scores = unique_tokens.map do |token|
      spam_likelihood, ham_likelihood = get_likelihoods(token)

      # Calculate the actual P(Spam|token) using the real priors
      # P(S|W) = P(W|S)P(S) / (P(W|S)P(S) + P(W|H)P(H))
      prob_word_given_spam = spam_likelihood * prob_spam_prior
      prob_word_given_ham = ham_likelihood * prob_ham_prior

      # Avoid division by zero if both are 0
      denominator = prob_word_given_spam + prob_word_given_ham
      next [ token, 0.5 ] if denominator == 0

      prob = prob_word_given_spam / denominator
      interestingness = (prob - 0.5).abs

      [ token, interestingness ]
    end

    # Select the top 15 most interesting tokens
    token_scores.sort_by { |_, interest| -interest }
      .first(15)
      .map { |token, _| token }
  end

  class << self
    def rebuild_all_public
      Rails.logger.info "Starting rebuild for all public classifiers..."

      # 1. Load all classifier states from the DB
      classifier_states = GroupClassifierState.for_public.index_by(&:group_id)

      # Reset stats in memory before starting
      classifier_states.each_value do |state|
        state.spam_counts = {}
        state.ham_counts = {}
        state.total_spam_words = 0
        state.total_ham_words = 0
        state.total_spam_messages = 0
        state.total_ham_messages = 0
        state.vocabulary_size = 0
      end

      # 2. Create a service instance for each state, injecting the state object
      services = classifier_states.transform_values do |state|
        new(state.group_id, state.group_name, classifier_state: state)
      end

      # 3. Process user name messages separately
      user_name_service = services[GroupClassifierState::USER_NAME_CLASSIFIER_GROUP_ID]
      if user_name_service
        TrainedMessage.trainable.for_user_name.find_each do |message|
          user_name_service.train_only(message)
        end
      end

      # 4. Process group content messages
      group_services = services.values.reject { |s| s.group_id == GroupClassifierState::USER_NAME_CLASSIFIER_GROUP_ID }

      # Create a single, temporary classifier state to aggregate results
      # This avoids training each group on the same data set individually.
      temp_state = GroupClassifierState.new(
        group_id: "temp",
        group_name: "temp",
        spam_counts: {},
        ham_counts: {},
        total_spam_words: 0,
        total_ham_words: 0,
        total_spam_messages: 0,
        total_ham_messages: 0,
        vocabulary_size: 0
      )
      temp_service = new(temp_state.group_id, temp_state.group_name, classifier_state: temp_state)

      # Train the temporary service once on all content messages
      TrainedMessage.trainable.for_message_content.find_each do |message|
        temp_service.train_only(message)
      end

      # Now, apply the aggregated state to all actual group services
      group_services.each do |service|
        state = service.classifier_state
        state.spam_counts         = temp_state.spam_counts.dup
        state.ham_counts          = temp_state.ham_counts.dup
        state.total_spam_words    = temp_state.total_spam_words
        state.total_ham_words     = temp_state.total_ham_words
        state.total_spam_messages = temp_state.total_spam_messages
        state.total_ham_messages  = temp_state.total_ham_messages
        state.vocabulary_size     = temp_state.vocabulary_size
      end

      # 5. Save everything in one transaction
      ActiveRecord::Base.transaction do
        services.each_value do |service|
          Rails.logger.info "Saving classifier for group_id: #{service.group_id}"
          service.classifier_state.save!
        end
      end

      Rails.logger.info "Classifier rebuild completed!"
    end
  end
end
