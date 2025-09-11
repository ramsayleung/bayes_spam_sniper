class TrainedMessagesController < ApplicationController
  before_action :set_trained_message, only: %i[ show edit update destroy ]

  # GET /trained_messages or /trained_messages.json
  def index
    @trained_messages = TrainedMessage.all

    if params[:message_type].present? && params[:message_type] != "all"
      @trained_messages = @trained_messages.where(message_type: params[:message_type])
    end

    if params[:training_target].present? && params[:training_target] != "all"
      @trained_messages = @trained_messages.where(training_target: params[:training_target])
    end

    if params[:group_name].present? && params[:group_name] != "all"
      @trained_messages = @trained_messages.where(group_name: params[:group_name])
    end

    if params[:search].present?
      @trained_messages = @trained_messages.where("message ILIKE ?", "%#{params[:search]}%")
    end

    # Sorting
    sort_by = params[:sort] || "created_at"
    sort_direction = params[:direction] || "desc"
    @trained_messages = @trained_messages.order("#{sort_by} #{sort_direction}")

    # Pagination
    @per_page = (params[:per_page] || 10).to_i
    @per_page = 10 if @per_page < 1 || @per_page > 100

    @total_count = @trained_messages.count
    @page = (params[:page] || 1).to_i
    @page = 1 if @page < 1

    offset = (@page - 1) * @per_page
    @trained_messages = @trained_messages.limit(@per_page).offset(offset)

    # Calculate pagination info
    @total_pages = (@total_count.to_f / @per_page).ceil

    # Using unscoped ensures we get all possible options, not just the filtered ones.
    filter_data = TrainedMessage.unscoped.distinct.pluck(:message_type, :training_target, :group_name)

    # Get filter options
    @message_types = filter_data.map(&:first).uniq.compact.sort
    @training_targets = filter_data.map(&:second).uniq.compact.sort
    @group_names = filter_data.map(&:third).uniq.compact.sort
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

  def bulk_update
    message_ids = params[:trained_message_ids]
    if message_ids.blank?
      redirect_to trained_messages_path(request.query_parameters), alter: "You must select at least one message."
      return
    end

    messages = TrainedMessage.where(id: message_ids)
    update_count = messages.count
    case params[:commit]
    when "Mark as Ham"
      messages.update_all(message_type: :ham)
      flash[:notice] = "Successfully marked #{update_count} messages as Ham"
    when "Mark as Spam"
      messages.update_all(message_type: :spam)
      flash[:notice] = "Successfully marked #{update_count} messages as Spam"
    else
      flash[:alert] = "Invalid action."
    end

    redirect_to trained_messages_path(
                  params.except(:commit, :trained_message_ids, :authenticity_token, :controller, :action).to_unsafe_h
                )
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
    return_url = params[:return_url] || trained_messages_path

    respond_to do |format|
      format.html { redirect_to return_url, notice: "Trained message was successfully destroyed.", status: :see_other }
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
    params.expect(trained_message: [ :group_id, :message, :message_type, :sender_chat_id, :sender_user_name, :group_name, :training_target ])
  end

  def index_params
    params.permit(:search, :message_type, :training_target, :group_name, :per_page, :sort, :direction, :page)
  end

  helper_method :index_params
end
