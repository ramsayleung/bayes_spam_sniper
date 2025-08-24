require "test_helper"

class GroupClassifierStatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @group_classifier_state = group_classifier_states(:one)
  end

  test "should get index" do
    get group_classifier_states_url
    assert_response :success
  end

  test "should get new" do
    get new_group_classifier_state_url
    assert_response :success
  end

  test "should create group_classifier_state" do
    assert_difference("GroupClassifierState.count") do
      post group_classifier_states_url, params: { group_classifier_state: { group_id: @group_classifier_state.group_id, ham_counts: @group_classifier_state.ham_counts, spam_counts: @group_classifier_state.spam_counts, total_ham_messages: @group_classifier_state.total_ham_messages, total_ham_words: @group_classifier_state.total_ham_words, total_spam_messages: @group_classifier_state.total_spam_messages, total_spam_words: @group_classifier_state.total_spam_words, vocabulary_size: @group_classifier_state.vocabulary_size } }
    end

    assert_redirected_to group_classifier_state_url(GroupClassifierState.last)
  end

  test "should show group_classifier_state" do
    get group_classifier_state_url(@group_classifier_state)
    assert_response :success
  end

  test "should get edit" do
    get edit_group_classifier_state_url(@group_classifier_state)
    assert_response :success
  end

  test "should update group_classifier_state" do
    patch group_classifier_state_url(@group_classifier_state), params: { group_classifier_state: { group_id: @group_classifier_state.group_id, ham_counts: @group_classifier_state.ham_counts, spam_counts: @group_classifier_state.spam_counts, total_ham_messages: @group_classifier_state.total_ham_messages, total_ham_words: @group_classifier_state.total_ham_words, total_spam_messages: @group_classifier_state.total_spam_messages, total_spam_words: @group_classifier_state.total_spam_words, vocabulary_size: @group_classifier_state.vocabulary_size } }
    assert_redirected_to group_classifier_state_url(@group_classifier_state)
  end

  test "should destroy group_classifier_state" do
    assert_difference("GroupClassifierState.count", -1) do
      delete group_classifier_state_url(@group_classifier_state)
    end

    assert_redirected_to group_classifier_states_url
  end
end
