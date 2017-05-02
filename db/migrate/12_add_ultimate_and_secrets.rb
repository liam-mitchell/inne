def get_attributes(file, names, starting_id)
  attributes = []

  if File.exist?(file)
    File.open(file).read.each_line.each_with_index do |l, i|
      l = l.delete("\n")

      if !l.empty?
        attributes << {id: i + starting_id, name: names[i], longname: l}
      end
    end
  end

  attributes
end

def shortname(tab, row, column, level = nil)
  column = "0" + column.to_s if column < 10
  level = "0" + level.to_s if level && level < 10

  [tab, row, column, level].compact.map(&:to_s).join("-")
end

def episode_id(episode)
  first_episodes = {"SU" => 480}

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

class AddUltimateAndSecrets < ActiveRecord::Migration[5.1]
  def change
    eps = (["SU"].product((0..19).to_a).product(["A", "B", "C", "D", "E"]) + ["SU"].product((0..19).to_a).product(["X"]))
    ue = eps.product((0..4).to_a)
          .map(&:flatten)
          .map { |l| shortname(l[0], l[2], l[1], l[3]) }

    ss = ["?"].product((0..23).to_a).product(["A", "B", "C", "D", "E"]).map(&:flatten).map { |l| shortname(l[0], l[2], l[1]) }
    ss2 = ["!"].product((0..23).to_a).product(["A", "B", "C", "D", "E"]).map(&:flatten).map { |l| shortname(l[0], l[2], l[1]) }

    attrs = get_attributes('names-SU.txt', ue, 2400) + get_attributes('names-SS.txt', ss, 1800) + get_attributes('names-SS2.txt', ss2, 3000)

    Level.create(attrs)

    epattrs = []
    eps.map(&:flatten).map { |e| shortname(e[0], e[2], e[1]) }.each { |e| epattrs << {name: e, id: episode_id(e)} }

    Episode.create(epattrs)
  end
end
