class FixUserlevelTabs < ActiveRecord::Migration[5.1]
  def change
    create_table :userlevel_tabs do |t|
      t.integer    :mode,      index: true, limit: 1
      t.integer    :qt,        index: true, limit: 1
      t.integer    :index,     index: true
      t.references :userlevel, index: true
    end
  end
end