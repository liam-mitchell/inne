# Users can choose a default mappack. Then, whenever a highscoreable is parsed
# from their message, it will be assumed to be from that mappack, rather than
# vanilla N++, thus saving the effort to write the 3 mappack code letters.
#
# mappack_id             - Mappack to use as global default
# mappack_defaults       - Use defaults for each channel (e.g. HAX in HAX channel)
# mappack_default_always - Use global default always
# mappacK_default_dms    - Use global default only on DMs

class AddPersonalPacks < ActiveRecord::Migration[5.1]
  def change
    add_column :users, :mappack_id,             :integer, default: 0
    add_column :users, :mappack_defaults,       :boolean, default: false
    add_column :users, :mappack_default_always, :boolean, default: false
    add_column :users, :mappack_default_dms,    :boolean, default: false
  end
end