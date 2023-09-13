# Move the Steam ID field over to the Players table, which makes more sense
class RefactorPlayers < ActiveRecord::Migration[5.1]
  def change
    add_column :players, :steam_id, :string
    add_column :players, :last_active, :timestamp
    add_column :players, :active, :boolean

    # Find players and userlevel_players
    User.where.not(steam_id: nil).each{ |u|
      if u.player
        u.player.update(
          steam_id:    u.steam_id,
          last_active: u.last_active,
          active:      u.active
        )
      else
        up = UserlevelPlayer.find_by(name: u.name)
        next if !up
        Player.where(metanet_id: up.metanet_id)
              .first_or_create(name: up.name)
              .update(
                steam_id:    u.steam_id,
                last_active: u.last_active,
                active:      u.active
              )
      end
    }

    remove_column :users, :steam_id
    remove_column :users, :last_active
    remove_column :users, :active
  end
end