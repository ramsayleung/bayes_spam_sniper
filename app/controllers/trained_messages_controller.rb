class TrainedMessagesController < ApplicationController
  before_action :set_trained_message, only: %i[ show edit update destroy ]

  # GET /trained_messages or /trained_messages.json
  def index
    @trained_messages = TrainedMessage.all
  end

  # GET /trained_messages/1 or /trained_messages/1.json
  def show
  end

  # GET /trained_messages/new
  def new
    @trained_message = TrainedMessage.new
  end

  # GET /trained_messages/1/edit
  def edit
  end

  # POST /trained_messages or /trained_messages.json
  def create
    @trained_message = TrainedMessage.new(trained_message_params)

    respond_to do |format|
      if @trained_message.save
        format.html { redirect_to @trained_message, notice: "Trained message was successfully created." }
        format.json { render :show, status: :created, location: @trained_message }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @trained_message.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /trained_messages/1 or /trained_messages/1.json
  def update
    respond_to do |format|
      if @trained_message.update(trained_message_params)
        format.html { redirect_to @trained_message, notice: "Trained message was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @trained_message }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @trained_message.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /trained_messages/1 or /trained_messages/1.json
  def destroy
    @trained_message.destroy!

    respond_to do |format|
      format.html { redirect_to trained_messages_path, notice: "Trained message was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_trained_message
      @trained_message = TrainedMessage.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def trained_message_params
      params.expect(trained_message: [ :group_id, :message, :message_type, :sender_chat_id ])
    end
end
