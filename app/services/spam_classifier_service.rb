require 'jieba_rb'

class SpamClassifierService
  attr_reader :group_id, :classifier_state

  def initialize(group_id)
    @group_id = group_id
    # Find the state for this group, or create a new one with default zero counts
    @classifier_state = GroupClassifierState.find_or_create_by!(group_id: @group_id) do |state|
      state.spam_counts = {}
      state.ham_counts = {}
      state.total_spam_words = 0
      state.total_ham_words = 0
      state.total_spam_messages = 0
      state.total_ham_messages = 0
      state.vocabulary_size = 0
    end
    @jieba = JiebaRb::Segment.new
  end

  def train(message_text, sender_id, sender_name, message_type)
    # 1. Save the individual training example
    TrainedMessage.create!(
      group_id: @group_id,
      message: message_text,
      sender_chat_id: sender_id,
      sender_user_name: sender_name,
      message_type: message_type
    )

    # 2. Update the aggregated classifier state for fast lookups
    tokens = tokenize(message_text)
    vocabulary = Set.new((@classifier_state.spam_counts.keys + @classifier_state.ham_counts.keys))

    if message_type == :spam
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
    @classifier_state.save!
  end

  def classify(message_text)
    # Return false if the model isn't trained enough
    return [false, 0.0, 0.0] if @classifier_state.total_ham_messages == 0 || @classifier_state.total_spam_messages == 0

    tokens = tokenize(message_text)
    total_messages = @classifier_state.total_spam_messages + @classifier_state.total_ham_messages

    # Calculate prior probabilities in log space
    prob_spam_prior = Math.log(@classifier_state.total_spam_messages.to_f / total_messages)
    prob_ham_prior = Math.log(@classifier_state.total_ham_messages.to_f / total_messages)

    spam_score = prob_spam_prior
    ham_score = prob_ham_prior
    
    vocab_size = @classifier_state.vocabulary_size

    tokens.each do |token|
      # Spam probability with Laplace smoothing
      spam_count = @classifier_state.spam_counts.fetch(token, 0) + 1
      spam_score += Math.log(spam_count.to_f / (@classifier_state.total_spam_words + vocab_size))

      # Ham probability with Laplace smoothing
      ham_count = @classifier_state.ham_counts.fetch(token, 0) + 1
      ham_score += Math.log(ham_count.to_f / (@classifier_state.total_ham_words + vocab_size))
    end
    
    is_spam = spam_score > ham_score
    [is_spam, spam_score, ham_score]
  end

  def retrain_as_ham(messages)
    # This is a critical action, so we use a transaction to ensure atomicity
    ActiveRecord::Base.transaction do
      state = classifier_state.reload # Reload to get the latest counts

      messages.each do |message|
        tokens = tokenize(message.message)

        state.total_spam_messages -= 1
        state.total_spam_words -= tokens.size
        tokens.each do |token|
          state.spam_counts[token] = state.spam_counts.fetch(token, 0) - 1
          state.spam_counts.delete(token) if state.spam_counts[token] <= 0
        end

        state.total_ham_messages += 1
        state.total_ham_words += tokens.size
        tokens.each do |token|
          state.ham_counts[token] = state.ham_counts.fetch(token, 0) + 1
        end

        message.update!(message_type: :ham)
      end

      # Recalculate vocabulary size
      vocabulary = Set.new((state.spam_counts.keys + state.ham_counts.keys))
      state.vocabulary_size = vocabulary.size
      state.save!
    end
  end

  private

  def tokenize(text)
    cleaned_text = clean_text(text)
    
    raw_tokens = @jieba.cut(cleaned_text)
    
    processed_tokens = raw_tokens
                         .reject(&:blank?)                    # Remove empty strings
                         .reject { |token| token.length < 2 } # Remove single characters (usually not meaningful)
                         .reject { |token| pure_punctuation?(token) } # Remove pure punctuation
                         .reject { |token| pure_numbers?(token) }     # Remove pure numbers
                         .map(&:downcase)                     # Normalize case (for mixed content)
    
    processed_tokens
  end

  def clean_text(text)
    return "" if text.nil?
    
    text = text.to_s.strip
    
    # Remove excessive whitespace
    text.gsub(/\s+/, ' ')
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
