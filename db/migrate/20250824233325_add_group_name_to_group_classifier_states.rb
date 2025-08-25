class AddGroupNameToGroupClassifierStates < ActiveRecord::Migration[8.0]
  def change
    add_column :group_classifier_states, :group_name, :string
  end
end
