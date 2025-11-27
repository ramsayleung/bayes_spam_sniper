class GroupClassifierStatesController < ApplicationController
  before_action :set_group_classifier_state, only: %i[ show edit update destroy ]

  # GET /group_classifier_states or /group_classifier_states.json
  def index
    @group_classifier_states = GroupClassifierState.all

    # Sorting
    sort_by = params[:sort] || "created_at"
    sort_direction = params[:direction] || "desc"
    @group_classifier_states = @group_classifier_states.order("#{sort_by} #{sort_direction}")

    # Pagination
    @per_page = (params[:per_page] || 10).to_i
    @per_page = 10 if @per_page < 1 || @per_page > 100

    @total_count = @group_classifier_states.count
    @page = (params[:page] || 1).to_i
    @page = 1 if @page < 1

    offset = (@page - 1) * @per_page
    @group_classifier_states = @group_classifier_states.limit(@per_page).offset(offset)

    # Calculate pagination info
    @total_pages = (@total_count.to_f / @per_page).ceil
  end

  # GET /group_classifier_states/1 or /group_classifier_states/1.json
  def show
    @k_value = @group_classifier_state.get_k_value(params[:k])
  end

  # GET /group_classifier_states/new
  def new
    @group_classifier_state = GroupClassifierState.new
  end

  # GET /group_classifier_states/1/edit
  def edit
  end

  # POST /group_classifier_states or /group_classifier_states.json
  def create
    @group_classifier_state = GroupClassifierState.new(group_classifier_state_params)

    respond_to do |format|
      if @group_classifier_state.save
        format.html { redirect_to @group_classifier_state, notice: "Group classifier state was successfully created." }
        format.json { render :show, status: :created, location: @group_classifier_state }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @group_classifier_state.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /group_classifier_states/1 or /group_classifier_states/1.json
  def update
    respond_to do |format|
      if @group_classifier_state.update(group_classifier_state_params)
        format.html { redirect_to @group_classifier_state, notice: "Group classifier state was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @group_classifier_state }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @group_classifier_state.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /group_classifier_states/1 or /group_classifier_states/1.json
  def destroy
    @group_classifier_state.destroy!

    respond_to do |format|
      format.html { redirect_to group_classifier_states_path, notice: "Group classifier state was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_group_classifier_state
      @group_classifier_state = GroupClassifierState.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def group_classifier_state_params
      params.expect(group_classifier_state: [ :group_id, :spam_counts, :ham_counts, :total_spam_words, :total_ham_words, :total_spam_messages, :total_ham_messages, :vocabulary_size ])
    end

  def index_params
    params.permit(:per_page, :sort, :direction, :page)
  end

  helper_method :index_params
end
