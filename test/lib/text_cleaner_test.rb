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

  test "#cleanup should handle any anti-spam separators" do
    spam_variants = [
      "合-约*报@单群组",
      "B#T@C$500点",
      "稳.赚.不.亏.的",
      "联,系,我,们"
    ]

    expected_variants = [
      "合约报单群组",
      "BTC500 点",
      "稳赚不亏的",
      "联系我们"
    ]

    spam_variants.each_with_index do |variant, index|
      expected_text = expected_variants[index]
      cleaned_text = TextCleaner.call(variant)
      cleaned_text = TextCleaner.call(variant)
      assert_equal expected_text, cleaned_text, "Failed on input: '#{variant}'"

      # Should NOT contain separator characters
      refute cleaned_text.match?(/[*@#$,.-]/)
    end
  end

  test "#call should handle punctuation correctly" do
    spam_message = "这人简-介挂的 合-约-报单群组挺牛的ETH500点，大饼5200点！ + @BTCETHl6666"
    cleaned_text = TextCleaner.call(spam_message)
    assert_equal "这人简介挂的合约报单群组挺牛的 ETH500 点大饼 5200 点！ + @BTCETHl6666", cleaned_text
  end
end
