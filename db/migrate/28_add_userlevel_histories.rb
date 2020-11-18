class AddUserlevelHistories < ActiveRecord::Migration[5.1]
  def change
    create_table :userlevel_histories do |t|
      t.timestamp  :timestamp, index: true
      t.integer    :rank,      index: true
      t.references :player
      t.integer    :metanet_id
      t.integer    :count
    end

    GlobalProperty.find_or_create_by(key: 'next_userlevel_history_update').update(value: (Time.now + 86400).to_s)
  end
end

