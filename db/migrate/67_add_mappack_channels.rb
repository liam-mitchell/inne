# We store a list of Discord channel IDs for each mappack, corresponding to the
# server channels that are dedicated to this mappack. This will be used when
# determining how highscoreable IDs are parsed by default for each player.
class AddMappackChannels < ActiveRecord::Migration[5.1]
  def change
    create_table :mappack_channels do |t|
      t.integer :mappack_id, index: true
      t.string :name
    end
  end
end