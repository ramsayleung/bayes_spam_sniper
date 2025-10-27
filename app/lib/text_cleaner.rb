class TextCleaner
  def self.call(text)
    new.clean(text)
  end


  def clean(text)
    return "" if text.nil?

    cleaned = text.to_s.strip

    cleaned = TextCleaner.extract_found_message(cleaned)

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

  # Extracts the message content after the #FOUND ... FROM ... prefix
  # '#FOUND "大哥" IN Open Source Community(@open_source_community)
  # FROM Bcjcnbj(8315776184) 大哥们快去抢 真有红包 手慢无'
  # will be cleaned to '大哥们快去抢 真有红包 手慢无'
  def self.extract_found_message(message)
    # Try to match the #FOUND pattern and extract everything after the first newline
    match = message.match(/^#FOUND\s+"[^"]+"\s+IN\s+[^(]+\(@?[^)]+\)\s+FROM\s+[^(]*\(@?[^)]+\)\s*(.*)/m)

    # Return the content if pattern matches, otherwise return the raw message
    match ? match[1] : message
  end

  private

  def remove_separators(text)
    previous = ""
    cleaned = text.dup
    while previous != cleaned
      previous = cleaned.dup
      cleaned = cleaned.gsub(/([一-龯A-Za-z0-9])[^一-龯A-Za-z0-9\s]+([一-龯A-Za-z0-9])/, '\1\2')
    end
    cleaned
  end

  def remove_chinese_spaces(text)
    previous = ""
    cleaned = text.dup
    while previous != cleaned
      previous = cleaned.dup
      cleaned = cleaned.gsub(/([一-龯])(\s+)([一-龯])/, '\1\3')
    end
    cleaned
  end

  def add_tokenization_spaces(text)
    text = text.gsub(/([一-龯])([A-Za-z0-9])/, '\1 \2')
    text.gsub(/([A-Za-z0-9])([一-龯])/, '\1 \2')
  end
end
