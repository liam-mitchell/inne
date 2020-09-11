class CreateUserlevelScores < ActiveRecord::Migration[5.1]
  def change
    create_table :userlevel_scores do |t|
      t.integer :userlevel_id, index: true
      t.integer :score
      t.integer :player_id, index: true
      t.integer :rank, limit: 1, index: true
      t.integer :tied_rank, limit: 1, index: true
      t.integer :replay_id
    end
  end
end
