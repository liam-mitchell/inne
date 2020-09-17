class AddRankingsUpdate < ActiveRecord::Migration[5.1]
  def change
    GlobalProperty.find_or_create_by(key: 'next_history_update').update(value: (Time.now + 86400).to_s)
  end
end
