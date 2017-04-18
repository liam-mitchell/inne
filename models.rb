require 'active_record'
require 'net/http'

IGNORED_PLAYERS = [
  "Kronogenics",
  "BlueIsTrue",
  "fiordhraoi",
]

$lock = Mutex.new

module HighScore
  def self.format_rank(rank)
    "#{rank < 10 ? '0' : ''}#{rank}"
  end

  def self.spreads(n, type)
    spreads = {}
    type.all.each do |elem|
      spread = elem.spread(n)
      if !spread.nil?
        spreads[elem.name] = spread
      end
    end
    spreads
  end

  def uri
    URI("https://dojo.nplusplus.ninja/prod/steam/get_scores?steam_id=76561197992013087&steam_auth=&#{self.class.to_s.downcase}_id=#{self.id.to_s}")
  end

  def get_scores
    response = Net::HTTP.get(uri)
    return nil if response == '-1337'
    return JSON.parse(response)['scores']
  end

  def update_scores(updated)
    updated = updated.select { |score| !IGNORED_PLAYERS.include?(score['user_name']) }

    $lock.synchronize do
      ActiveRecord::Base.transaction do
        updated.each_with_index do |score, i|
          scores.find_or_create_by(rank: i)
            .update(
              score: score['score'] / 1000.0,
              player: Player.find_or_create_by(name: score['user_name']),
              tied_rank: updated.find_index { |s| s['score'] == score['score'] }
            )
        end
      end
    end
  end

  def download_scores
    updated = get_scores

    if updated.nil?
      # TODO make this use err()
      STDERR.puts "[ERROR] [#{Time.now}] failed to retrieve scores from #{uri}"
      return
    end

    update_scores(updated)

    puts "downloaded scores from #{uri}"
  end

  def spread(n)
    scores.find_by(rank: n).spread unless !scores.exists?(rank: n)
  end

  def format_scores
    scores.map(&:format).join("\n")
  end

  def difference(old)
    scores.map do |score|
      oldscore = old.find { |o| o['player']['name'] == score.player.name }
      change = nil

      if oldscore
        change = {rank: oldscore['rank'] - score.rank, score: score.score - oldscore['score']}
      end

      {score: score, change: change}
    end
  end

  def format_difference(old)
    difference(old).map { |o|
      c = o[:change]
      diff = "#{"++-"[c[:rank] <=> 0]}#{c[:rank].abs}, +#{".3f" % [o[:score]]}"
      "#{s[:score].format} (#{s[:diff]})"
    }
  end
end

class Level < ActiveRecord::Base
  include HighScore
  has_many :scores, as: :highscoreable

  def format_name
    "#{longname} (#{name})"
  end
end

class Episode < ActiveRecord::Base
  include HighScore
  has_many :scores, as: :highscoreable

  def format_name
    "#{name}"
  end
end

class Score < ActiveRecord::Base
  belongs_to :player
  belongs_to :highscoreable, polymorphic: true

  def spread
    highscoreable.scores.find_by(rank: 0).score - score
  end

  def format
    "#{HighScore.format_rank(rank)}: #{player.name} (#{"%.3f" % [score]})"
  end
end

class Player < ActiveRecord::Base
  has_many :scores
  has_one :user

  def self.rankings(&block)
    Player.includes(:scores).all.map { |p| [p, yield(p)] }
      .sort_by { |a| -a[1] }
  end

  def scores_by_type(type)
    type ? scores.where(highscoreable_type: type.to_s) : scores
  end

  def top_ns(n, type, ties)
    scores_by_type(type).all.select do |s|
      (ties ? s.tied_rank : s.rank) < n
    end
  end

  def top_n_count(n, type, ties)
    top_ns(n, type, ties).count
  end

  def scores_by_rank(type = nil)
    ret = Array.new(20, [])
    scores_by_type(type).group_by(&:rank).sort_by(&:first).each { |rank, scores| ret[rank] = scores }
    ret
  end

  def score_counts
    {
      levels: scores_by_rank(Level).map(&:length).map(&:to_i),
      episodes: scores_by_rank(Episode).map(&:length).map(&:to_i)
    }
  end

  def missing_top_ns(n, type, ties)
    levels = top_ns(n, type, ties).map { |s| s.highscoreable.name }

    if type
      type.where.not(name: levels).pluck(:name)
    else
      Level.where.not(name: levels).pluck(:name) + Episode.where.not(name: levels).pluck(:name)
    end
  end

  def improvable_scores(type = nil)
    improvable = {}
    scores_by_type(type).each { |s| improvable[s.highscoreable.name] = s.spread }
    improvable
  end

  def points(type = nil)
    scores_by_type(type).pluck(:rank).map { |rank| 20 - rank }.reduce(0, :+)
  end

  def total_score(type = nil)
    scores_by_type(type).pluck(:score).reduce(0, :+)
  end
end

class User < ActiveRecord::Base
  belongs_to :player
end

class GlobalProperty < ActiveRecord::Base
end
