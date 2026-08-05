class AddHouseholdToUsers < ActiveRecord::Migration[8.1]
  def change
    add_reference :users, :household, null: false, foreign_key: true
    add_column :users, :name, :string
  end
end
