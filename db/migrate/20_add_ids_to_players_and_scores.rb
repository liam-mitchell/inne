class AddIdsToPlayersAndScores < ActiveRecord::Migration[5.1]
  def change
    change_table :players do |t|
      t.integer :metanet_id
    end
    change_table :scores do |t|
      t.integer :replay_id
    end
  end
end
