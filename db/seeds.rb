def level_id(level)
  episode_id(level) * 5 + level[/[0-9][0-9]$/].to_i
end

def episode_id(episode)
  first_episodes = {"SI" => 0, "S" => 120, "SL" => 240}

  prefix, row, column = episode.split("-")
  column = column.to_i

  id = first_episodes[prefix.upcase]

  if row !~ /X/i
    id += column * 5
    id += row.upcase.ord - "A".ord
  else
    id += column + 100
  end

  id
end

def all_levels(episodes)
  episodes.product((0..4).to_a).map { |a| a.join("-0") }
end

def all_episodes
  intro = ["SI"].product(["A", "B", "C", "D", "E"])
          .product((0..4).to_a)

  # TODO FIX THIS
  # but we never seed shit so whatevs
  main = ["S", "SL"].product(["A", "B", "C", "D", "E", "X"])
         .product((0..19).to_a)

  (intro + main).map(&:flatten).map do |prefix, row, column|
    column = "0" + column.to_s if column < 10
    [prefix, row, column.to_s].join("-")
  end
end

def get_names(file, starting_id)
  names = {}
  if File.exist?(file)
    File.open(file).read.each_line.each_with_index do |l, i|
      l = l.delete("\n")

      if !l.empty?
        names[i + starting_id] = {longname: l}
      end
    end
  end
  names
end

episodes = all_episodes
levels = all_levels(episodes)

ActiveRecord::Base.transaction do
  Episode.create(episodes.map { |e| {id: episode_id(e), name: e} })
  Level.create(levels.map { |l| {id: level_id(l), name: l} })

  if File.exist?('completed.json')
    completed = JSON.parse(File.read('completed.json'))
    Episode.where(name: completed['episodes']).update_all(completed: true)
    Level.where(name: completed['levels']).update_all(completed: true)
  end

  names = get_names('db/names/names-SI.txt', 0)
          .merge(get_names('db/names/names-S.txt', 600))
          .merge(get_names('db/names/names-SL.txt', 1200))
  Level.update(names.keys, names.values)

  now = Time.now
  next_level_update = DateTime.new(now.year, now.month, now.day + 1, 0, 0, 0, now.zone)
  next_episode_update = next_level_update

  while !next_episode_update.saturday?
    next_episode_update = next_episode_update + 1
  end

  next_level_update = next_level_update.to_time
  next_episode_update = next_episode_update.to_time

  GlobalProperty.find_or_create_by(key: 'current_level'       , value: 'SL-C-10-00')
  GlobalProperty.find_or_create_by(key: 'current_episode'     , value: 'SL-C-00')
  GlobalProperty.find_or_create_by(key: 'next_level_update'   , value: next_level_update.to_s)
  GlobalProperty.find_or_create_by(key: 'next_episode_update' , value: next_episode_update.to_s)
  GlobalProperty.find_or_create_by(key: 'next_score_update'   , value: next_level_update.to_s)
  GlobalProperty.find_or_create_by(key: 'saved_level_scores'  , value: Level.find_by(name: 'SL-C-10-00').scores.to_json(include: {player: {only: :name}}))
  GlobalProperty.find_or_create_by(key: 'saved_episode_scores', value: Episode.find_by(name: 'SL-C-00').scores.to_json(include: {player: {only: :name}}))
  GlobalProperty.find_or_create_by(key: "last_steam_id"       , value: '76561198031272062')

end
