class CreatePredictions < ActiveRecord::Migration[8.1]
  def change
    create_table :predictions do |t|
      # NOTE: no standalone user_id index; the composite unique index below covers user lookups.
      t.references :user, null: false, foreign_key: true, index: false
      t.references :fixture, null: false, foreign_key: true
      t.integer :home_score, null: false
      t.integer :away_score, null: false
      t.integer :points_awarded

      t.timestamps
    end
    add_index :predictions, [ :user_id, :fixture_id ], unique: true
  end
end
