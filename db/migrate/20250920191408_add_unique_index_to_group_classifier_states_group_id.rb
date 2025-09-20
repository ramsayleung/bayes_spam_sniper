class AddUniqueIndexToGroupClassifierStatesGroupId < ActiveRecord::Migration[8.0]
  def change
    # Remove the old, non-unique index first.
    remove_index :group_classifier_states, name: "index_group_classifier_states_on_group_id"

    # Now, add the new index with a uniqueness constraint.
    add_index :group_classifier_states, :group_id, unique: true
  end
end
