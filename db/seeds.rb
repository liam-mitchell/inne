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

  main = ["S", "SL"].product(["A", "B", "C", "D", "E", "X"])
         .product((0..19).to_a)

  (intro + main).map(&:flatten).map do |prefix, row, column|
    column = "0" + column.to_s if column < 10
    [prefix, row, column.to_s].join("-")
  end
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
end
