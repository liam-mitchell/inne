class AddGoldCounts < ActiveRecord::Migration[5.1]
  def change
    add_column :mappack_levels,   :gold, :integer, limit: 2
    add_column :mappack_episodes, :gold, :integer, limit: 2
    add_column :mappack_stories,  :gold, :integer, limit: 2

    level_count   = MappackLevel.count
    episode_count = MappackEpisode.count
    story_count   = MappackStory.count
    MappackLevel.find_each.with_index{ |l, i|
      dbg("Setting gold count for level #{i + 1} / #{level_count}...", progress: true)
      l.update(gold: l.gold)
    }
    Log.clear
    MappackEpisode.find_each.with_index{ |e, i|
      dbg("Setting gold count for episode #{i + 1} / #{episode_count}...", progress: true)
      e.update(gold: MappackLevel.where(episode: e).sum(:gold))
    }
    Log.clear
    MappackStory.find_each.with_index{ |s, i|
      dbg("Setting gold count for story #{i + 1} / #{story_count}...", progress: true)
      s.update(gold: MappackEpisode.where(story: s).sum(:gold))
    }
    Log.clear
  end
end