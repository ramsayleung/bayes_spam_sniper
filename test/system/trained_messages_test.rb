require "application_system_test_case"
require "ostruct"
require "minitest/mock"

class TrainedMessagesTest < ApplicationSystemTestCase
  setup do
    @trained_message = trained_messages(:one)
  end

  test "visiting the index" do
    visit trained_messages_url
    assert_selector "h1", text: "Trained Messages"
  end

  test "should create trained message" do
    TelegramMemberFetcher.stub(:get_bot_chat_member, OpenStruct.new(status: "administrator", can_restrict_members: true)) do
      visit trained_messages_url
      click_on "New trained message"

      fill_in "Group", with: @trained_message.group_id
      fill_in "Message", with: @trained_message.message
      select "Spam", from: "Message type"
      select "Message Content", from: "Training target"
      fill_in "Sender chat", with: @trained_message.sender_chat_id
      click_on "Create Trained message"

      assert_text "Trained message was successfully created"
      click_on "Back"
    end
  end

  test "should update Trained message" do
    visit trained_message_url(@trained_message)
    click_on "Edit this trained message", match: :first

    fill_in "Group", with: @trained_message.group_id
    fill_in "Message", with: @trained_message.message
    select "Spam", from: "Message type"
    select "Message Content", from: "Training target"
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
