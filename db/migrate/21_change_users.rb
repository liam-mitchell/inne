# WARNING: This migration is not reversible, use with care!

class ChangeUsers < ActiveRecord::Migration[5.1]
  # From now on, Players will only be created by the bot itself, so
  # users will reference player names instead of player ids.
  def change
    change_table :users do |t|
      t.string :playername
    end
    User.all.each{ |u|
      u.playername = (Player.find(u.player_id).name rescue nil)
      u.save
    }
    change_table :users do |t|
      t.remove :player_id
    end
  end
end
