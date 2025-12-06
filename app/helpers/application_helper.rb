module ApplicationHelper
  # Extracts the message content after the #FOUND ... FROM ... prefix
  # FOUND "大哥" IN Open Source Community(@open_source_community) FROM Bcjcnbj(8315776184) 大哥们快去抢 真有红包 手慢无
  # 大哥们快去抢 真有红包 手慢无
  def extract_message_content(raw_message)
    TextCleaner.extract_found_message(raw_message)
  end

  def marked_by_classes(marked_by_value)
    case marked_by_value
    when "group_admin"
      "bg-blue-100 text-blue-800"
    when "admin_dashboard"
      "bg-purple-100 text-purple-800"
    when "auto_sync"
      "bg-yellow-100 text-yellow-800"
    else
      "bg-gray-100 text-gray-800"
    end
  end
end
