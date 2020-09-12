class CreateUserlevelPlayers < ActiveRecord::Migration[5.1]
  def change
    create_table :userlevel_players do |t|
      t.string :name
      t.integer :metanet_id
    end
  end
end
