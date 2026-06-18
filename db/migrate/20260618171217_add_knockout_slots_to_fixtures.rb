class AddKnockoutSlotsToFixtures < ActiveRecord::Migration[8.1]
  def change
    change_column_null :fixtures, :home_team_id, true
    change_column_null :fixtures, :away_team_id, true
    add_column :fixtures, :home_slot_label, :string
    add_column :fixtures, :away_slot_label, :string
    add_column :fixtures, :match_number, :integer
  end
end
