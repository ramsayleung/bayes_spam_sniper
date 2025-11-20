class AddLanguageToGroupClassifierStates < ActiveRecord::Migration[8.1]
  def change
    add_column :group_classifier_states, :language, :string
  end
end
