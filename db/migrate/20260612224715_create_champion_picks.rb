class CreateChampionPicks < ActiveRecord::Migration[8.1]
  def change
    create_table :champion_picks do |t|
      # One champion pick per user.
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.references :team, null: false, foreign_key: true

      t.timestamps
    end
  end
end
