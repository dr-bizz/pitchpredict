class BackfillKnockoutSlots < ActiveRecord::Migration[8.1]
  def up
    KnockoutReset.call
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
