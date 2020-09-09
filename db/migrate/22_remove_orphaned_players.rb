class RemoveOrphanedPlayers < ActiveRecord::Migration[5.1]
  # We remove every player that does not have a non-null Metanet ID field.
  # This means that the player has never had a highscore since tracking began:
  # it is orphaned (ie. never used) and is therefore useless.
  #
  # We also remove orphaned scores, ie., those belonging to players we
  # just removed.
  def change
    players = Player.where(metanet_id: nil)
    count = players.size
    players.each_with_index{ |p, i|
      print("Removing player #{i} of #{count}...".ljust(80, " ") + "\r")
      p.destroy
    }
    scores = Score.where(replay_id: nil)
    count = scores.size
    scores.each_with_index{ |s, i|
      print("Removing score #{i} of #{count}...".ljust(80, " ") + "\r")
      s.destroy
    }
  end
end
