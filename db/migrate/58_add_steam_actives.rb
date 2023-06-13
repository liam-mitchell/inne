class AddSteamActives < ActiveRecord::Migration[5.1]
  def change
    change_table :users do |t|
      t.remove :last_inactive
      t.boolean :active, index: true
    end

    GlobalProperty.update_steam_actives
  end
end