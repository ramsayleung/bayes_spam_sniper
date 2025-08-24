require "test_helper"

class TrainedMessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @trained_message = trained_messages(:one)
  end

  test "should get index" do
    get trained_messages_url
    assert_response :success
  end

  test "should get new" do
    get new_trained_message_url
    assert_response :success
  end

  test "should create trained_message" do
    assert_difference("TrainedMessage.count") do
      post trained_messages_url, params: { trained_message: { group_id: @trained_message.group_id, message: @trained_message.message, message_type: @trained_message.message_type, sender_chat_id: @trained_message.sender_chat_id } }
    end

    assert_redirected_to trained_message_url(TrainedMessage.last)
  end

  test "should show trained_message" do
    get trained_message_url(@trained_message)
    assert_response :success
  end

  test "should get edit" do
    get edit_trained_message_url(@trained_message)
    assert_response :success
  end

  test "should update trained_message" do
    patch trained_message_url(@trained_message), params: { trained_message: { group_id: @trained_message.group_id, message: @trained_message.message, message_type: @trained_message.message_type, sender_chat_id: @trained_message.sender_chat_id } }
    assert_redirected_to trained_message_url(@trained_message)
  end

  test "should destroy trained_message" do
    assert_difference("TrainedMessage.count", -1) do
      delete trained_message_url(@trained_message)
    end

    assert_redirected_to trained_messages_url
  end
end
