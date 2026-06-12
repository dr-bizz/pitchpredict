class CreateTeams < ActiveRecord::Migration[8.1]
  def change
    create_table :teams do |t|
      t.string :name, null: false
      t.string :code, null: false
      # NOTE: column is group_name (not "group") to avoid the SQL GROUP keyword.
      t.string :group_name, null: false
      t.string :flag_emoji
      t.string :confederation

      t.timestamps
    end
    add_index :teams, :code, unique: true
    add_index :teams, :group_name
  end
end
