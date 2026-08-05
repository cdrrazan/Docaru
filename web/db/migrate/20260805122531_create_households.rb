class CreateHouseholds < ActiveRecord::Migration[8.1]
  def change
    create_table :households do |t|
      t.string :name, null: false
      # Plans gate storage, never alerts. Paywalling the safety feature would
      # poison the trust the whole product rests on, so every tier keeps every
      # reminder and every playbook.
      t.string :plan, null: false, default: "free"

      t.timestamps
    end
  end
end
