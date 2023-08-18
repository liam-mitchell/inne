# Users can choose a default mappack. Then, whenever a highscoreable is parsed
# from their message, it will be assumed to be from that mappack, rather than
# vanilla N++, thus saving the effort to write the 3 mappack code letters.
class AddPersonalPacks < ActiveRecord::Migration[5.1]
  def change
    add_column :users, :mappack_id, :integer, default: 0
  end
end