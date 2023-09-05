# Users can choose a default mappack. Then, whenever a highscoreable is parsed
# from their message, it will be assumed to be from that mappack, rather than
# vanilla N++, thus saving the effort to write the 3 mappack code letters.
# This default can be configured to be used on the mappack's channels, on DMS,
# or always.
class AddPersonalPacks < ActiveRecord::Migration[5.1]
  def change
    add_column :users, :mappack_id,          :integer, default: 0
    add_column :users, :default_on_dms,      :boolean, default: false
    add_column :users, :default_on_channels, :boolean, default: false
    add_column :users, :default_on_rest,     :boolean, default: false
  end
end