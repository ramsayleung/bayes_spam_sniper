class RuleBasedClassifier
  CHINESE_SPACING_THRESHOLD = Rails.application.config.chinese_space_spam_threshold

  def initialize(message_text)
    @message_text = message_text
  end

  def classify
    result = check_chinese_spacing_spam
    if result.is_spam
      return result
    end

    result
  end

  private

  def check_chinese_spacing_spam
    min_chinese_chars = 5
    # This pattern specifically looks for a Chinese character, followed by a space,
    # and then another Chinese character like this
    # 跟 单 像 捡 钱 ！ 再 不 进 群 是 傻 狗 ！
    # 懷 疑 有 特 異 功 能 ！ 總 能 提 前 知 道 ！
    if @message_text.match?(/\p{Han}/)
      # Count Chinese characters that are immediately followed by a space.
      # The lookahead `(?=\s)` ensures the space itself is not included in the match,
      # so we can count only the characters.
      spaced_chinese_words_count = @message_text.scan(/\p{Han}(?=\s)/).size
      chinese_chars = @message_text.scan(/\p{Han}/).size

      threshold = Rails.application.config.chinese_space_spam_threshold
      ratio = chinese_chars > 0 ? spaced_chinese_words_count.to_f / chinese_chars : 0.0

      if ratio > threshold && chinese_chars >= min_chinese_chars
        Rails.logger.info "Classified as spam due to high Chinese character spacing ratio: #{ratio}"
        return Shared::ClassificationResult.new(is_spam: true, target: "message_content", p_spam: 1)
      end
    end
    Shared::ClassificationResult.new(is_spam: false, target: nil, p_spam: 0)
  end
end
