class CreateFixtures < ActiveRecord::Migration[8.1]
  def change
    create_table :fixtures do |t|
      t.references :home_team, null: false, foreign_key: { to_table: :teams }
      t.references :away_team, null: false, foreign_key: { to_table: :teams }
      t.references :stadium, null: false, foreign_key: true
      t.datetime :kickoff_at, null: false
      t.integer :stage, null: false, default: 0
      # NOTE: scores stay NULL until the match has been played.
      t.integer :home_score
      t.integer :away_score
      t.integer :status, null: false, default: 0

      t.timestamps
    end
    add_index :fixtures, :kickoff_at
  end
end
