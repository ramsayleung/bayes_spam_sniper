class BannedUsersController < ApplicationController
  before_action :set_banned_user, only: %i[ show edit update destroy ]

  # GET /banned_users or /banned_users.json
  def index
    @banned_users = BannedUser.all
  end

  # GET /banned_users/1 or /banned_users/1.json
  def show
  end

  # GET /banned_users/new
  def new
    @banned_user = BannedUser.new
  end

  # GET /banned_users/1/edit
  def edit
  end

  # POST /banned_users or /banned_users.json
  def create
    @banned_user = BannedUser.new(banned_user_params)

    respond_to do |format|
      if @banned_user.save
        format.html { redirect_to @banned_user, notice: "Banned user was successfully created." }
        format.json { render :show, status: :created, location: @banned_user }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @banned_user.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /banned_users/1 or /banned_users/1.json
  def update
    respond_to do |format|
      if @banned_user.update(banned_user_params)
        format.html { redirect_to @banned_user, notice: "Banned user was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @banned_user }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @banned_user.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /banned_users/1 or /banned_users/1.json
  def destroy
    @banned_user.destroy!

    respond_to do |format|
      format.html { redirect_to banned_users_path, notice: "Banned user was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_banned_user
      @banned_user = BannedUser.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def banned_user_params
      params.expect(banned_user: [ :group_id, :sender_chat_id, :sender_user_name, :spam_message ])
    end
end
