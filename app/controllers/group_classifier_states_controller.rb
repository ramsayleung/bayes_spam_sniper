class GroupClassifierStatesController < ApplicationController
  before_action :set_group_classifier_state, only: %i[ show edit update destroy ]

  # GET /group_classifier_states or /group_classifier_states.json
  def index
    @group_classifier_states = GroupClassifierState.all
  end

  # GET /group_classifier_states/1 or /group_classifier_states/1.json
  def show
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
      @group_classifier_state = GroupClassifierState.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def group_classifier_state_params
      params.expect(group_classifier_state: [ :group_id, :spam_counts, :ham_counts, :total_spam_words, :total_ham_words, :total_spam_messages, :total_ham_messages, :vocabulary_size ])
    end
end
