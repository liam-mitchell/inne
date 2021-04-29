class AddDatesToSteamIds < ActiveRecord::Migration[5.1]
  def change
    add_column :users, :last_active,   :timestamp
    add_column :users, :last_inactive, :timestamp
  end
end
