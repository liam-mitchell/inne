class AddLastUserlevelUpdate < ActiveRecord::Migration[5.1]
  def change
    add_column :userlevels, :last_update, :timestamp
  end
end
