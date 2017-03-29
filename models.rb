require 'active_record'
require 'net/http'

IGNORED_PLAYERS = [
  "Kronogenics",
  "BlueIsTrue",
  "fiordhraoi",
]

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

  def download_scores
    response = Net::HTTP.get(uri)

    if response == '-1337'
      # TODO make this use err()
      STDERR.puts "[ERROR] [#{Time.now}] failed to retrieve scores from #{uri}"
      return
    end

    updated = JSON.parse(response)['scores']
      .select { |score| !IGNORED_PLAYERS.include?(score['user_name']) }

    ActiveRecord::Base.transaction do
      updated.each_with_index do |score, i|
        scores.find_or_create_by(rank: i)
          .update(score: score['score'] / 1000.0, player: Player.find_or_create_by(name: score['user_name']))
      end
    end
  end

  def spread(n)
    scores.find_by(rank: n).spread unless !scores.exists?(rank: n)
  end

  def format_scores
    scores.map(&:format).join("\n")
  end

  def format_difference(old)
    old = JSON.parse(old)
    scores.map do |score|
      oldscore = old.find { |orig| orig["player"]["name"] == score.player.name }
      diff = "new"

      if oldscore
        change = oldscore["rank"] - score.rank
        change = "#{"++-"[change <=> 0]}#{change.abs}"
        scorechange = oldscore["score"] - score.score
        scorechange = "#{"++-"[scorechange <=> 0]}#{"%.3f" % [scorechange.abs]}"
        diff = "#{change}, #{scorechange}"
      end

      "#{score.format} (#{diff})"
    end.join("\n")
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

  def self.parse(msg, username)
    p = msg[/for (.*)[\.\?]?/i, 1]

    if p.nil?
      raise "I couldn't find a player with your username! Have you identified yourself (with '@inne++ my name is <N++ display name>')?" unless User.exists?(username: username)
      User.find_by(username: username).player
    else
      Player.find_or_create_by(name: p)
    end
  end

  def self.top_n_rankings(n, type, ties)
    Player.all.map { |p| [p, p.top_n_count(n, type, ties)] }
      .sort_by { |a| -a[1] }
  end

  def scores_by_type(type)
    type ? scores.where(highscoreable_type: type.to_s) : scores
  end

  def top_n_count(n, type, ties)
    scores_by_type(type).all.select do |s|
      s.rank < n || (ties && s.highscoreable.scores.find_by(rank: n - 1).score == s.score)
    end.count
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

  def missing_scores(type)
    type.where.not(id: type.joins(:scores).where(scores: {player: self}).pluck(:id)).pluck(:name)
  end

  def improvable_scores(type = nil)
    improvable = {}
    scores_by_type(type).each { |s| improvable[s.highscoreable.name] = s.spread }
    improvable
  end

  def points(type = nil)
    scores_by_type(type).pluck(:rank).map { |rank| 20 - rank }.reduce(0, :+)
  end
end

class User < ActiveRecord::Base
  belongs_to :player
end
