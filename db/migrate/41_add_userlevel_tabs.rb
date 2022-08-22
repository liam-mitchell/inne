# Position of userlevels in each of the userlevel tabs (best, featured,
# top weekly and hardest).
class AddUserlevelTabs < ActiveRecord::Migration[5.1]
  def change
    create_table :userlevel_tabs do |t|
      t.integer    :mode,      index: true, limit: 1
      t.integer    :qt,        index: true, limit: 1
      t.integer    :index,     index: true
      t.references :userlevel, index: true
    end
    GlobalProperty.find_or_create_by(key: 'next_userlevel_tab_update').update(value: Time.now.to_s)
  end
end