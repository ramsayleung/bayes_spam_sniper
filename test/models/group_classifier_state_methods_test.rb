require "test_helper"

class GroupClassifierStateMethodsTest < ActiveSupport::TestCase
  def setup
    @classifier = GroupClassifierState.new(
      spam_counts: { "hello" => 10, "world" => 5, "spam" => 15, "test" => 3 },
      ham_counts: { "good" => 8, "morning" => 12, "ham" => 6, "nice" => 4 }
    )
  end

  test "top_spam_words returns top N spam words" do
    top_spam = @classifier.top_spam_words(2)
    assert_equal [ [ "spam", 15 ], [ "hello", 10 ] ], top_spam
  end

  test "top_ham_words returns top N ham words" do
    top_ham = @classifier.top_ham_words(2)
    assert_equal [ [ "morning", 12 ], [ "good", 8 ] ], top_ham
  end
end
