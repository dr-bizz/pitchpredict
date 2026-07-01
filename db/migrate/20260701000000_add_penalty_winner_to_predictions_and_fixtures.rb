class AddPenaltyWinnerToPredictionsAndFixtures < ActiveRecord::Migration[8.1]
  def change
    add_column :predictions, :penalty_winner, :integer
    add_column :fixtures, :penalty_winner, :integer
  end
end
