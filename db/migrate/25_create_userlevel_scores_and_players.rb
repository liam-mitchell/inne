class CreateUserlevelScoresAndPlayers < ActiveRecord::Migration[5.1]
  def change
    create_table :userlevel_scores do |t|
      t.integer :userlevel_id, index: true
      t.integer :score
      t.integer :player_id, index: true
      t.integer :rank, limit: 1, index: true
      t.integer :tied_rank, limit: 1, index: true
      t.integer :replay_id
    end

    create_table :userlevel_players do |t|
      t.string :name
      t.integer :metanet_id
    end

    GlobalProperty.find_or_create_by(key: 'next_userlevel_score_update').update(value: (Time.now + 86400).to_s)
    GlobalProperty.find_or_create_by(key: 'next_userlevel_report_update').update(value: (Time.now + 86400).to_s)
  end
end
