class AddStarToScores < ActiveRecord::Migration[5.1]
  def change
    add_column :scores, :cool, :boolean, default: false, index: true
    add_column :scores, :star, :boolean, default: false, index: true
    add_index  :archives, :framecount
    add_index  :archives, :gold
    [Level, Episode, Story].each{ |type|
      total = type.count
      type.all.each_with_index{ |h, i|
        print("Adding cool and star to #{type.to_s.downcase} #{i + 1} / #{total}...".ljust(80, ' ') + "\r")
        coolness = h.find_coolness
        stars    = Archive.zeroths(h)
        h.scores.where("rank < #{coolness}").update_all(cool: true)
        h.scores.joins("INNER JOIN players ON players.id = scores.player_id")
                .where({ "players.metanet_id" => stars }).update_all(star: true)
      }
    }
  end
end