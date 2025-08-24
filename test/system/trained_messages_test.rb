require "application_system_test_case"

class TrainedMessagesTest < ApplicationSystemTestCase
  setup do
    @trained_message = trained_messages(:one)
  end

  test "visiting the index" do
    visit trained_messages_url
    assert_selector "h1", text: "Trained messages"
  end

  test "should create trained message" do
    visit trained_messages_url
    click_on "New trained message"

    fill_in "Group", with: @trained_message.group_id
    fill_in "Message", with: @trained_message.message
    fill_in "Message type", with: @trained_message.message_type
    fill_in "Sender chat", with: @trained_message.sender_chat_id
    click_on "Create Trained message"

    assert_text "Trained message was successfully created"
    click_on "Back"
  end

  test "should update Trained message" do
    visit trained_message_url(@trained_message)
    click_on "Edit this trained message", match: :first

    fill_in "Group", with: @trained_message.group_id
    fill_in "Message", with: @trained_message.message
    fill_in "Message type", with: @trained_message.message_type
    fill_in "Sender chat", with: @trained_message.sender_chat_id
    click_on "Update Trained message"

    assert_text "Trained message was successfully updated"
    click_on "Back"
  end

  test "should destroy Trained message" do
    visit trained_message_url(@trained_message)
    accept_confirm { click_on "Destroy this trained message", match: :first }

    assert_text "Trained message was successfully destroyed"
  end
end
