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

  def self.spreads(n, type, tabs)
    spreads = {}
    scores = tabs.empty? ? type.all : type.where(tab: tabs)

    scores.each do |elem|
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
      diff = c ? "#{"++-"[c[:rank] <=> 0]}#{c[:rank].abs}, +#{"%.3f" % [c[:score]]}" : "new"
      "#{o[:score].format} (#{diff})"
    }.join("\n")
  end
end

class Level < ActiveRecord::Base
  include HighScore
  has_many :scores, as: :highscoreable
  enum tab: [:SI, :S, :SU, :SL, :SS, :SS2]

  def format_name
    "#{longname} (#{name})"
  end
end

class Episode < ActiveRecord::Base
  include HighScore
  has_many :scores, as: :highscoreable
  enum tab: [:SI, :S, :SU, :SL, :SS, :SS2]

  def format_name
    "#{name}"
  end
end

class Score < ActiveRecord::Base
  belongs_to :player
  belongs_to :highscoreable, polymorphic: true
  belongs_to :level, -> { where(scores: {highscoreable_type: 'Level'}) }, foreign_key: 'highscoreable_id'
  belongs_to :episode, -> { where(scores: {highscoreable_type: 'Episode'}) }, foreign_key: 'highscoreable_id'

  def spread
    highscoreable.scores.find_by(rank: 0).score - score
  end

  def format
    "#{HighScore.format_rank(rank)}: #{player.name} (#{"%.3f" % [score]})"
  end
end

class Player < ActiveRecord::Base
  has_many :scores
  has_many :rank_histories
  has_many :points_histories
  has_many :total_score_histories
  has_one :user

  def self.rankings(&block)
    players = $lock.synchronize do
      Player.includes(:scores).all
    end

    players.map { |p| [p, yield(p)] }
      .sort_by { |a| -a[1] }
  end

  def self.histories(type, attrs, column)
    hist = $lock.synchronize do
      type.where(attrs).includes(:player)
    end

    ret = Hash.new { |h, k| h[k] = Hash.new { |h, k| h[k] = 0 } }

    hist.each do |h|
      ret[h.player.name][h.timestamp] += h.send(column)
    end

    ret
  end

  def self.rank_histories(rank, type, tabs, ties)
    attrs = {rank: rank, ties: ties}
    attrs[:highscoreable_type] = type.to_s if type
    attrs[:tab] = tabs if !tabs.empty?

    self.histories(RankHistory, attrs, :count)
  end

  def self.score_histories(type, tabs)
    attrs = {}
    attrs[:highscoreable_type] = type.to_s if type
    attrs[:tab] = tabs if !tabs.empty?

    self.histories(TotalScoreHistory, attrs, :score)
  end

  def self.points_histories(type, tabs)
    attrs = {}
    attrs[:highscoreable_type] = type.to_s if type
    attrs[:tab] = tabs if !tabs.empty?

    self.histories(PointsHistory, attrs, :points)
  end

  def scores_by_type_and_tabs(type, tabs)
    ret = type ? scores.where(highscoreable_type: type.to_s) : scores
    ret = tabs.empty? ? ret : ret.includes(:level).where(levels: {tab: tabs}) + ret.includes(:episode).where(episodes: {tab: tabs})
    ret
  end

  def top_ns(n, type, tabs, ties)
    scores_by_type_and_tabs(type, tabs).select do |s|
      (ties ? s.tied_rank : s.rank) < n
    end
  end

  def top_n_count(n, type, tabs, ties)
    top_ns(n, type, tabs, ties).count
  end

  def scores_by_rank(type, tabs)
    ret = Array.new(20, [])
    scores_by_type_and_tabs(type, tabs).group_by(&:rank).sort_by(&:first).each { |rank, scores| ret[rank] = scores }
    ret
  end

  def score_counts(tabs)
    {
      levels: scores_by_rank(Level, tabs).map(&:length).map(&:to_i),
      episodes: scores_by_rank(Episode, tabs).map(&:length).map(&:to_i)
    }
  end

  def missing_top_ns(n, type, tabs, ties)
    levels = top_ns(n, type, tabs, ties).map { |s| s.highscoreable.name }

    if type
      type.where(tab: tabs).where.not(name: levels).pluck(:name)
    else
      Level.where(tab: tabs).where.not(name: levels).pluck(:name) + Episode.where(tab: tabs).where.not(name: levels).pluck(:name)
    end
  end

  def improvable_scores(type, tabs)
    improvable = {}
    scores_by_type_and_tabs(type, tabs).each { |s| improvable[s.highscoreable.name] = s.spread }
    improvable
  end

  def points(type, tabs)
    scores_by_type_and_tabs(type, tabs).pluck(:rank).map { |rank| 20 - rank }.reduce(0, :+)
  end

  def total_score(type, tabs)
    scores_by_type_and_tabs(type, tabs).pluck(:score).reduce(0, :+)
  end
end

class User < ActiveRecord::Base
  belongs_to :player
end

class GlobalProperty < ActiveRecord::Base
end

class RankHistory < ActiveRecord::Base
  belongs_to :player
  enum tab: [:SI, :S, :SU, :SL, :SS, :SS2]
end

class PointsHistory < ActiveRecord::Base
  belongs_to :player
  enum tab: [:SI, :S, :SU, :SL, :SS, :SS2]
end

class TotalScoreHistory < ActiveRecord::Base
  belongs_to :player
  enum tab: [:SI, :S, :SU, :SL, :SS, :SS2]
end
