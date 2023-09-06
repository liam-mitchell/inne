# Refactor the users table to make it simpler and more robust, by referencing
# the corresponding player by ID, uniformizing column names, etc.
class RefactorUsers < ActiveRecord::Migration[5.1]
  def change
    add_column    :users, :player_id, :integer
    rename_column :users, :username, :name
    remove_column :users, :displayname

    User.where.not(playername: nil).each{ |u|
      player = Player.find_by(name: u.playername)
      next if !player
      u.update(player_id: player.id)
    }

    remove_column :users, :playername
  end
end