class CreateStadia < ActiveRecord::Migration[8.1]
  def change
    create_table :stadia do |t|
      t.string :name, null: false
      t.string :city, null: false
      t.string :country, null: false

      t.timestamps
    end
  end
end
