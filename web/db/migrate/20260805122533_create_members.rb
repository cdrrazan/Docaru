class CreateMembers < ActiveRecord::Migration[8.1]
  def change
    create_table :members do |t|
      t.references :household, null: false, foreign_key: true
      # A member is a person documents belong to, not a person who logs in.
      # Children, and parents whose paperwork is being managed from another
      # country, are members without ever being users — which is the case the
      # spec's diaspora wedge is built around.
      t.string :name, null: false
      t.string :relationship

      t.timestamps
    end
  end
end
