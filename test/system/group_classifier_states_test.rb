require "application_system_test_case"

class GroupClassifierStatesTest < ApplicationSystemTestCase
  setup do
    @group_classifier_state = group_classifier_states(:one)
  end

  test "visiting the index" do
    visit group_classifier_states_url
    assert_selector "h1", text: "Group classifier"
  end

  test "should create group classifier state" do
    visit group_classifier_states_url
    click_on "New Group Classifier"

    fill_in "Group", with: 99
    fill_in "Ham counts", with: @group_classifier_state.ham_counts
    fill_in "Spam counts", with: @group_classifier_state.spam_counts
    fill_in "Total ham messages", with: @group_classifier_state.total_ham_messages
    fill_in "Total ham words", with: @group_classifier_state.total_ham_words
    fill_in "Total spam messages", with: @group_classifier_state.total_spam_messages
    fill_in "Total spam words", with: @group_classifier_state.total_spam_words
    fill_in "Vocabulary size", with: @group_classifier_state.vocabulary_size
    click_on "Create Group classifier state"

    assert_text "Group classifier state was successfully created"
    click_on "Back"
  end

  test "should update Group classifier state" do
    visit group_classifier_state_url(@group_classifier_state)
    click_on "Edit this group classifier state", match: :first

    fill_in "Group", with: @group_classifier_state.group_id
    fill_in "Ham counts", with: @group_classifier_state.ham_counts
    fill_in "Spam counts", with: @group_classifier_state.spam_counts
    fill_in "Total ham messages", with: @group_classifier_state.total_ham_messages
    fill_in "Total ham words", with: @group_classifier_state.total_ham_words
    fill_in "Total spam messages", with: @group_classifier_state.total_spam_messages
    fill_in "Total spam words", with: @group_classifier_state.total_spam_words
    fill_in "Vocabulary size", with: @group_classifier_state.vocabulary_size
    click_on "Update Group classifier state"

    assert_text "Group classifier state was successfully updated"
    click_on "Back"
  end

  test "should destroy Group classifier state" do
    visit group_classifier_state_url(@group_classifier_state)
    accept_confirm { click_on "Destroy this group classifier state", match: :first }

    assert_text "Group classifier state was successfully destroyed"
  end
end
