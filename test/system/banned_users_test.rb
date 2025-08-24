require "application_system_test_case"

class BannedUsersTest < ApplicationSystemTestCase
  setup do
    @banned_user = banned_users(:one)
  end

  test "visiting the index" do
    visit banned_users_url
    assert_selector "h1", text: "Banned users"
  end

  test "should create banned user" do
    visit banned_users_url
    click_on "New banned user"

    fill_in "Group", with: @banned_user.group_id
    fill_in "Sender chat", with: @banned_user.sender_chat_id
    fill_in "Sender user name", with: @banned_user.sender_user_name
    fill_in "Spam message", with: @banned_user.spam_message
    click_on "Create Banned user"

    assert_text "Banned user was successfully created"
    click_on "Back"
  end

  test "should update Banned user" do
    visit banned_user_url(@banned_user)
    click_on "Edit this banned user", match: :first

    fill_in "Group", with: @banned_user.group_id
    fill_in "Sender chat", with: @banned_user.sender_chat_id
    fill_in "Sender user name", with: @banned_user.sender_user_name
    fill_in "Spam message", with: @banned_user.spam_message
    click_on "Update Banned user"

    assert_text "Banned user was successfully updated"
    click_on "Back"
  end

  test "should destroy Banned user" do
    visit banned_user_url(@banned_user)
    accept_confirm { click_on "Destroy this banned user", match: :first }

    assert_text "Banned user was successfully destroyed"
  end
end
