module ApplicationHelper
  # Extracts the message content after the #FOUND ... FROM ... prefix
  # FOUND "大哥" IN Open Source Community(@open_source_community) FROM Bcjcnbj(8315776184) 大哥们快去抢 真有红包 手慢无
  # 大哥们快去抢 真有红包 手慢无
  def extract_message_content(raw_message)
    TextCleaner.extract_found_message(raw_message)
  end
end
