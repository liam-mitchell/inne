class AddSteamIdToUsers < ActiveRecord::Migration[5.1]
    def change
        change_table :users do |t|
            t.column :steam_id, :string
        end
    end
end
