require "test_helper"

class TextCleanerTest < ActiveSupport::TestCase
  test "extracts message content from #FOUND pattern" do
    input = '#FOUND "大哥" IN Open Source Community(@open_source_community) FROM Bcjcnbj(8315776184) 大哥们快去抢 真有红包 手慢无'
    expected = "大哥们快去抢 真有红包 手慢无"
    assert_equal expected, TextCleaner.extract_found_message(input)

    input = '#FOUND "大佬" IN Log(@adblockerlog) FROM Log(@adblockerlog) ⏱️ 处理时间: 🟡 4.7秒 📝 收到消息 群组: Clash Party讨论群(原 Mihomo Party) (-1002349280849) 链接: https://t.me/mihomo_party_group/110367 内容: 别上班了，lai和大佬跑优😊，两月开路虎😎，看zhu ye 用户: 让我利口酒 (8346296964) 用户名: @xnnxdukbx 置信度: 初始： '
    expected = "⏱️ 处理时间: 🟡 4.7秒 📝 收到消息 群组: Clash Party讨论群(原 Mihomo Party) (-1002349280849) 链接: https://t.me/mihomo_party_group/110367 内容: 别上班了，lai和大佬跑优😊，两月开路虎😎，看zhu ye 用户: 让我利口酒 (8346296964) 用户名: @xnnxdukbx 置信度: 初始： "
    assert_equal expected, TextCleaner.extract_found_message(input)
  end
end
