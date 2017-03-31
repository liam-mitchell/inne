class CreateGlobalProperties < ActiveRecord::Migration
  def change
    create_table :global_properties do |t|
      t.string :key, index: true
      t.string :value, index: true
    end

    now = Time.now
    next_level_update = DateTime.new(now.year, now.month, now.day + 1, 0, 0, 0, now.zone)
    next_episode_update = next_level_update

    while !next_episode_update.saturday?
      next_episode_update = next_episode_update + 1
    end

    next_level_update = next_level_update.to_time
    next_episode_update = next_episode_update.to_time

    # lol this is wrong
    # if current_level is S-C-18-01 why are saved_level_scores from SL-C-10-00
    GlobalProperty.create(key: 'current_level', value: 'S-C-18-01')
    GlobalProperty.create(key: 'current_episode', value: 'SL-C-00')
    GlobalProperty.create(key: 'next_level_update', value: next_level_update.to_s)
    GlobalProperty.create(key: 'next_episode_update', value: next_episode_update.to_s)
    GlobalProperty.create(key: 'saved_level_scores', value: Level.find_by(name: 'SL-C-10-00').scores.to_json(include: {player: {only: :name}}))
    GlobalProperty.create(key: 'saved_episode_scores', value: Episode.find_by(name: 'SL-C-00').scores.to_json(include: {player: {only: :name}}))
  end
end
