# Merge userlevel players together with players.
#
# Notes:
#   They were originally separated for performance related reasons which are no
#   longer relevant, plus now that we store both Steam IDs and display names in
#   the players table, we need to merge them so that those two features are
#   available for userlevels. Nevertheless, we also 
class RefactorUserlevelPlayers < ActiveRecord::Migration[5.1]
  def change
    # Add a field that keeps track of which players have Metanet scores, so that
    # we can filter them quickly for Metanet queries if needed.
    add_column :players, :metanet, :boolean, index: true, default: false
    Player.update_all(metanet: true)

    # We need to temporarily store the metanet ID in the userlevel scores table
    # so that we can later update the player IDs, which will change during the
    # migration.
    add_column :userlevel_scores, :metanet_id, :integer
    count = UserlevelPlayer.count
    pad = count.to_s.length
    i = 1

    # Migrate userlevel players over to the players table, bar duplicates
    UserlevelPlayer.find_each{ |up|
      print("Migrating userlevel player #{"%#{pad}d" % i} / #{count}...".ljust(80, ' ') + "\r")

      # Store metanet_id and create new player if it doesn't already exist
      UserlevelScore.where(player: up).update_all(metanet_id: up.metanet_id)
      p = Player.where(metanet_id: up.metanet_id)
                .first_or_create(metanet_id: up.metanet_id, name: up.name)

      # Update player_id fields in tables that reference userlevel_players
      if p.id != up.id
        UserlevelScore.where(metanet_id: up.metanet_id).update_all(player_id: p.id)
        UserlevelHistory.where(metanet_id: up.metanet_id).update_all(player_id: p.id)
      end

      i += 1
    }
    puts ' ' * 80

    # metanet_id fields no longer needed
    remove_column :userlevel_scores, :metanet_id
    remove_column :userlevel_histories, :metanet_id
  end
end