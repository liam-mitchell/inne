# coding: utf-8
require 'active_record'
require 'net/http'
require 'chunky_png' # for screenshot generation
include ChunkyPNG::Color

ATTEMPT_LIMIT   = 20    # redownload retries until we move on to the next level
SHOW_ERRORS     = false # log common error messages

SCORE_PADDING   =  0    #         fixed    padding, 0 for no fixed padding
DEFAULT_PADDING = 15    # default variable padding, never make 0
MAX_PADDING     = 15    # max     variable padding, 0 for no maximum
TRUNCATE_NAME   = true  # truncate name when it exceeds the maximum padding

# ID ranges for levels and episodes, and score limits to filter new hacked scores
TABS = {
  "Episode" => {
    :SI => [ (  0.. 24).to_a, 400],
    :S  => [ (120..239).to_a, 950],
    :SL => [ (240..359).to_a, 650],
    :SU => [ (480..599).to_a, 650]
  },
  "Level" => {
    :SI  => [ (  0..  124).to_a,  298],
    :S   => [ ( 600..1199).to_a,  874],
    :SL  => [ (1200..1799).to_a,  400],
    :SS  => [ (1800..1919).to_a, 2462],
    :SU  => [ (2400..2999).to_a,  530],
    :SS2 => [ (3000..3119).to_a,  322]
  },
  "Story" => {
    :SI => [ ( 0..  4).to_a, 1000],
    :S  => [ (24.. 43).to_a, 2000],
    :SL => [ (48.. 67).to_a, 2000],
    :SU => [ (96..115).to_a, 1500]
  }
}

IGNORED_PLAYERS = [
  "Kronogenics",
  "BlueIsTrue",
  "fiordhraoi",
  "cheeseburgur101",
  "Jey",
  "jungletek",
  "Hedgy",
  "ᕈᘎᑕᒎᗩn ᙡiᗴᒪḰi",
  "Venom",
  "EpicGamer10075",
  "Altii",
  "Pu𝐜ͥⷮⷮⷮⷮͥⷮͥⷮe",
  "Floof The Goof",
  "Prismo",
  "Mishu",
  "dimitry008",
  "Chara",
  "test8378",
  "VexatiousCheff"
]

# Problematic hackers? We get rid of them by banning their user IDs
IGNORED_IDS = [
  115572, # Mishu
  201322, # dimitry008
  146275, # Puce
  253161, # Chara
  253072, # test8378
  221472  # VexatiousCheff
]

# Turn a little endian binary array into an integer
def parse_int(bytes)
  if bytes.is_a?(Array) then bytes = bytes.join end
  bytes.unpack('H*')[0].scan(/../).reverse.join.to_i(16)
end

# Reformat date strings received by queries to the server
def format_date(date)
  date.gsub!(/-/,"/")
  date[-6] = " "
  date = date[2..-1]
  date[0..7].split("/").reverse.join("/") + date[-6..-1]
end

# Convert an integer into a little endian binary string of 'size' bytes and back
def _pack(n, size)
  n.to_s(16).rjust(2 * size, "0").scan(/../).reverse.map{ |b|
    [b].pack('H*')[0]
  }.join.force_encoding("ascii-8bit")
end

def _unpack(bytes)
  if bytes.is_a?(Array) then bytes = bytes.join end
  bytes.unpack('H*')[0].scan(/../).reverse.join.to_i(16)
end

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

  def self.ties(type, tabs)
    ties = []
    scores = tabs.empty? ? type.all : type.where(tab: tabs)

    scores.each do |elem|
      tie_count = elem.tie_count
      if !tie_count.nil? && tie_count >= 3
        ties << [elem, tie_count, elem.scores.size]
      end
    end

    ties
  end

  def scores_uri(steam_id)
    URI("https://dojo.nplusplus.ninja/prod/steam/get_scores?steam_id=#{steam_id}&steam_auth=&#{self.class.to_s.downcase}_id=#{self.id.to_s}")
  end

  def replay_uri(steam_id, replay_id)
    URI("https://dojo.nplusplus.ninja/prod/steam/get_replay?steam_id=#{steam_id}&steam_auth=&replay_id=#{replay_id}")
  end

  def get_scores
    initial_id = get_last_steam_id
    attempts ||= 0
    response = Net::HTTP.get(scores_uri(initial_id))
    while response == '-1337'
      update_last_steam_id
      break if get_last_steam_id == initial_id
      response = Net::HTTP.get(scores_uri(get_last_steam_id))
    end
    return nil if response == '-1337'
    correct_ties(JSON.parse(response)['scores'])
  rescue => e
    if (attempts += 1) < ATTEMPT_LIMIT
      if SHOW_ERRORS
        err("error getting scores for #{self.class.to_s.downcase} with id #{self.id.to_s}: #{e}")
      end
      retry
    else
      return nil
    end
  end

  def get_replay(replay_id)
    initial_id = get_last_steam_id
    response = Net::HTTP.get(replay_uri(initial_id, replay_id))
    while response == '-1337'
      update_last_steam_id
      break if get_last_steam_id == initial_id
      response = Net::HTTP.get(replay_uri(get_last_steam_id, replay_id))
    end
    return nil if response == '-1337'
    response
  rescue => e
    if SHOW_ERRORS
      err("error getting replay with id #{replay_id}: #{e}")
    end
    retry
  end

  def save_scores(updated)
    updated = updated.select { |score|
      limit = TABS[self.class.to_s].map{ |k, v| v[1] }.max
      TABS[self.class.to_s].each{ |k, v| if v[0].include?(self.id) then limit = v[1]; break end  }
      !IGNORED_PLAYERS.include?(score['user_name']) && !IGNORED_IDS.include?(score['user_id']) && score['score'] / 1000.0 < limit
    }.uniq { |score| score['user_name'] }

    ActiveRecord::Base.transaction do
      updated.each_with_index do |score, i|
        player = Player.find_or_create_by(metanet_id: score['user_id'])
        player.update(name: score['user_name'].force_encoding('UTF-8'))
        scores.find_or_create_by(rank: i).update(
          score: score['score'] / 1000.0,
          replay_id: score['replay_id'].to_i,
          player: player,
          tied_rank: updated.find_index { |s| s['score'] == score['score'] }
        )
        if Archive.find_by(replay_id: score['replay_id'], highscoreable_type: self.class.to_s).nil?
          ar = Archive.create(
            replay_id: score['replay_id'].to_i,
            player: Player.find_by(metanet_id: score['user_id']),
            highscoreable: self,
            score: (score['score'] * 60.0 / 1000.0).round,
            metanet_id: score['user_id'].to_i, # future-proof the db
            date: Time.now
          )
          demo = Demo.find_or_create_by(replay_id: ar.replay_id)
          demo.update(id: ar.id)
          demo.update_demo
        end
      end
      # Remove scores stuck at the bottom after ignoring cheaters
      scores.where(rank: (updated.size..19).to_a).delete_all
    end
  end

  def update_scores
    updated = get_scores

    if updated.nil?
      if SHOW_ERRORS
        # TODO make this use err()
        STDERR.puts "[WARNING] [#{Time.now}] failed to retrieve scores from #{scores_uri(get_last_steam_id)}"
      end
      return -1
    end

    save_scores(updated)
  rescue => e
    if SHOW_ERRORS
      err("error updating database with level #{self.id.to_s}: #{e}")
    end
    return -1
  end

  def get_replay_info(rank)
    updated = get_scores

    if updated.nil?
      if SHOW_ERRORS
        # TODO make this use err()
        STDERR.puts "[WARNING] [#{Time.now}] failed to retrieve replay info from #{scores_uri(get_last_steam_id)}"
      end
      return
    end

    updated.select { |score| !IGNORED_PLAYERS.include?(score['user_name']) }.uniq { |score| score['user_name'] }[rank]
  end

  def analyze_replay(replay_id)
    replay = get_replay(replay_id)
    demo = Zlib::Inflate.inflate(replay[16..-1])[30..-1]
    analysis = demo.unpack('H*')[0].scan(/../).map{ |b| b.to_i }[1..-1]
  end

  def correct_ties(score_hash)
    score_hash.sort_by{ |s| [-s['score'], s['replay_id']] }
  end

  def spread(n)
    scores.find_by(rank: n).spread unless !scores.exists?(rank: n)
  end

  def tie_count
    scores.take_while{ |s| s.tie }.count
  end

  def max_name_length
    scores.map{ |s| s.player.name.length }.max
  end

  def format_scores(padding = DEFAULT_PADDING)
    max = scores.map(&:score).max.to_i.to_s.length + 4
    scores.map{ |s| s.format(padding, max) }.join("\n")
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
    diffs = difference(old)

    name_padding = scores.map{ |s| s.player.name.length }.max
    score_padding = scores.map{ |s| s.score.to_i }.max.to_s.length + 4
    rank_padding = diffs.map{ |d| d[:change] }.compact.map{ |d| d[:rank].to_i }.max.to_s.length
    change_padding = diffs.map{ |d| d[:change] }.compact.map{ |d| d[:score].to_i }.max.to_s.length + 4

    difference(old).map { |o|
      c = o[:change]
      diff = c ? "#{"++-"[c[:rank] <=> 0]}#{"%#{rank_padding}d" % [c[:rank].abs]}, +#{"%#{change_padding}.3f" % [c[:score]]}" : "new"
      "#{o[:score].format(name_padding, score_padding)} (#{diff})"
    }.join("\n")
  end
end

class Level < ActiveRecord::Base
  include HighScore
  has_many :scores, as: :highscoreable
  has_many :videos, as: :highscoreable
  enum tab: [:SI, :S, :SU, :SL, :SS, :SS2]

  def format_name
    "#{longname} (#{name})"
  end
end

class Episode < ActiveRecord::Base
  include HighScore
  has_many :scores, as: :highscoreable
  has_many :videos, as: :highscoreable
  enum tab: [:SI, :S, :SU, :SL, :SS, :SS2]

  def format_name
    "#{name}"
  end

  def cleanliness(rank = 0)
    [name, Level.where("UPPER(name) LIKE ?", name.upcase + '%').map{ |l| l.scores[0].score }.sum - scores[rank].score - 360]
  end

  def ownage
    owner = scores[0].player.name
    [name, Level.where("UPPER(name) LIKE ?", name.upcase + '%').map{ |l| l.scores[0].player.name == owner }.count(true) == 5, owner]
  end

  def splits(rank = 0)
    acc = 90
    Level.where("UPPER(name) LIKE ?", name.upcase + '%').map{ |l| acc += l.scores[rank].score - 90 }
  rescue
    nil
  end
end

class Story < ActiveRecord::Base
  include HighScore
  has_many :scores, as: :highscoreable
  has_many :videos, as: :highscoreable
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
  belongs_to :story, -> { where(scores: {highscoreable_type: 'Story'}) }, foreign_key: 'highscoreable_id'
  default_scope -> { select("scores.*, score * 1.000 as score")} # Ensure 3 correct decimal places

  def self.total_scores(type, tabs, secrets)
    tabs = (tabs.empty? ? [:SI, :S, :SL, :SU, :SS, :SS2] : tabs)
    tabs = (secrets ? tabs : tabs - [:SS, :SS2])
    query = self.where(rank: 0, highscoreable_type: type.to_s)
    result = (
      query.includes(:level).where(levels: {tab: tabs}) +
      query.includes(:episode).where(episodes: {tab: tabs}) +
      query.includes(:story).where(stories: {tab: tabs})
    ).map{ |s| s.score }
    [result.sum, result.count]
  end

  def spread
    highscoreable.scores.find_by(rank: 0).score - score
  end

  def tie
    highscoreable.scores.find_by(rank: 0).score == score
  end

  def format(name_padding = DEFAULT_PADDING, score_padding = 0)
    "#{HighScore.format_rank(rank)}: #{player.format_name(name_padding)} - #{"%#{score_padding}.3f" % [score]}"
  end
end

# Note: Players used to be referenced by Users, not anymore. Everything has been
# structured to better deal with multiple players and/or users with the same name.
class Player < ActiveRecord::Base
  has_many :scores
  has_many :rank_histories
  has_many :points_histories
  has_many :total_score_histories

  def self.rankings(&block)
    players = Player.all

    players.map { |p| [p, yield(p)] }
      .sort_by { |a| -a[1] }
  end

  def self.histories(type, attrs, column)
    attrs[:highscoreable_type] ||= ['Level', 'Episode'] # Don't include stories
    hist = type.where(attrs).includes(:player)

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

  def format_name(padding = DEFAULT_PADDING)
    if SCORE_PADDING > 0 # FIXED padding mode
      "%-#{"%d" % [SCORE_PADDING]}s" % [name]
    else                 # VARIABLE padding mode
      if MAX_PADDING > 0   # maximum padding supplied
        if padding > 0       # valid padding
          if padding <= MAX_PADDING
            "%-#{"%d" % [padding]}s" % [name]
          else
            "%-#{"%d" % [MAX_PADDING]}s" % [TRUNCATE_NAME ? name.slice(0,MAX_PADDING) : name]
          end
        else                 # invalid padding
          "%-#{"%d" % [DEFAULT_PADDING]}s" % [name]
        end
      else                 # maximum padding not supplied
        if padding > 0       # valid padding
          "%-#{"%d" % [padding]}s" % [name]
        else                 # invalid padding
          "%-#{"%d" % [DEFAULT_PADDING]}s" % [name]
        end
      end
    end
  end

  def scores_by_type_and_tabs(type, tabs)
    ret = type ? scores.where(highscoreable_type: type.to_s) : scores.where(highscoreable_type: ["Level", "Episode"])
    ret = tabs.empty? ? ret : ret.includes(:level).where(levels: {tab: tabs}) + ret.includes(:episode).where(episodes: {tab: tabs}) + ret.includes(:story).where(stories: {tab: tabs})
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
      episodes: scores_by_rank(Episode, tabs).map(&:length).map(&:to_i),
      stories: scores_by_rank(Story, tabs).map(&:length).map(&:to_i)
    }
  end

  def missing_top_ns(n, type, tabs, ties)
    levels = top_ns(n, type, tabs, ties).map { |s| s.highscoreable.name }

    tabs = (tabs.empty? ? [:SI, :S, :SL, :SU, :SS, :SS2] : tabs)
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

  def average_points(type, tabs)
    scores = scores_by_type_and_tabs(type, tabs).pluck(:rank).map { |rank| 20 - rank }
    scores.length == 0 ? 0 : scores.reduce(0, :+).to_f / scores.length
  end

  def total_score(type, tabs)
    scores_by_type_and_tabs(type, tabs).pluck(:score).reduce(0, :+)
  end
end

class User < ActiveRecord::Base
  def player
    Player.find_by(name: playername)
  end
  def player=(person)
    name = person.class == Player ? person.name : person.to_s
    self.playername = name
    self.save
  end
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

class Video < ActiveRecord::Base
  belongs_to :highscoreable, polymorphic: true

  def format_challenge
    return (challenge == "G++" || challenge == "?!") ? challenge : "#{challenge} (#{challenge_code})"
  end

  def format_author
    return "#{author} (#{author_tag})"
  end

  def format_description
    "#{format_challenge} by #{format_author}"
  end
end

class Archive < ActiveRecord::Base
  belongs_to :player
  belongs_to :highscoreable, polymorphic: true

  # Returns the leaderboards at a particular point in time
  def self.scores(highscoreable, date)
    self.select('metanet_id', 'max(score)')
        .where(highscoreable: highscoreable)
        .where("unix_timestamp(date) <= #{date}")
        .group('metanet_id')
        .order('max(score) desc')
        .take(20)
        .map{ |s|
          [s.metanet_id.to_i, s['max(score)'].to_i]
        }
  end

  def find_rank(time)
    old_score = Archive.scores(self.highscoreable, time)
                       .each_with_index
                       .map{ |s, i| [i, s[0], s[1]] }
                       .select{ |s| s[1] == self.metanet_id }
    old_score.empty? ? 20 : old_score.first[0]
  end

  def format_score
    "%.3f" % self.score.to_f / 60.0
  end

  def demo
    Demo.find_by(replay_id: self.replay_id).demo
  end

end

class Demo < ActiveRecord::Base
  #----------------------------------------------------------------------------#
  #                    METANET REPLAY FORMAT DOCUMENTATION                     |
  #----------------------------------------------------------------------------#
  # REPLAY DATA:                                                               |
  #    4B  - Query type                                                        |
  #    4B  - Replay ID                                                         |
  #    4B  - Level ID                                                          |
  #    4B  - User ID                                                           |
  #   Rest - Demo data compressed with zlib                                    |
  #----------------------------------------------------------------------------#
  # LEVEL DEMO DATA FORMAT:                                                    |
  #     1B - Unknown                                                           |
  #     4B - Data length                                                       |
  #     4B - Unknown                                                           |
  #     4B - Frame count                                                       |
  #     4B - Level ID                                                          |
  #    13B - Unknown                                                           |
  #   Rest - Demo                                                              |
  #----------------------------------------------------------------------------#
  # EPISODE DEMO DATA FORMAT:                                                  |
  #     4B - Unknown                                                           |
  #    20B - Block length for each level demo (5 * 4B)                         |
  #   Rest - Demo data (5 consecutive blocks, see above)                       |
  #----------------------------------------------------------------------------#
  # STORY DEMO DATA FORMAT:                                                    |
  #     4B - Unknown                                                           |
  #     4B - Demo data block size                                              |
  #   100B - Block length for each level demo (25 * 4B)                        |
  #   Rest - Demo data (25 consecutive blocks, see above)                      |
  #----------------------------------------------------------------------------#
  # DEMO FORMAT:                                                               |
  #   * One byte per frame.                                                    |
  #   * First bit for jump, second for right and third for left.               |
  #   * Suicide is 12 (0C).                                                    |
  #   * The first frame is fictional and must be ignored.                      |
  #----------------------------------------------------------------------------#

  def score
    Archive.find_by(replay_id: self.replay_id)
  end

  def type
    score.highscoreable_type
  end

  def qt
    case type
    when "Level"
      0
    when "Episode"
      1
    when "Story"
      4
    else
      -1 # error checking
    end
  end

  def demo_uri(steam_id)
    URI.parse("https://dojo.nplusplus.ninja/prod/steam/get_replay?steam_id=#{steam_id}&steam_auth=&replay_id=#{replay_id}&qt=#{qt}")
  end

  def get_demo
    attempts ||= 0
    initial_id = get_last_steam_id
    response = Net::HTTP.get_response(demo_uri(initial_id))
    while response.body == '-1337'
      update_last_steam_id
      break if get_last_steam_id == initial_id
      response = Net::HTTP.get_response(demo_uri(get_last_steam_id))
    end
    return -1 if response.code.to_i == 200 && response.body.empty? # replay does not exist
    return nil if response.body == '-1337'
    raise "502 Bad Gateway" if response.code.to_i == 502
    response.body
  rescue => e
    if (attempts += 1) < ATTEMPT_LIMIT
      if SHOW_ERRORS
        err("error getting demo with id #{replay_id}: #{e}")
      end
      retry
    else
      return nil
    end
  end

  def parse_demo(replay)
    data   = Zlib::Inflate.inflate(replay[16..-1])
    header = {level: 0, episode:  4, story:   8}[type.downcase.to_sym]
    offset = {level: 0, episode: 24, story: 108}[type.downcase.to_sym]
    count  = {level: 1, episode:  5, story:  25}[type.downcase.to_sym]

    lengths = (0..count - 1).map{ |d| _unpack(data[header + 4 * d..header + 4 * (d + 1) - 1]) }
    lengths = [_unpack(data[1..4])] if type == "Level"
    (0..count - 1).map{ |d|
      offset += lengths[d - 1] unless d == 0
      data[offset..offset + lengths[d] - 1][30..-1]
    }
  end

  def encode_demo(replay)
    replay = [replay] if replay.class == String
    Zlib::Deflate.deflate(replay.join('&'), 9)
  end

  def decode_demo(data)
    demos = Zlib::Inflate.inflate(data).split('&')
    return (demos.size == 1 ? demos.first : demos)
  end

  def update_demo
    replay = get_demo
    return nil if replay.nil? # replay was not fetched successfully
    if replay == -1 # replay does not exist
      ActiveRecord::Base.transaction do
        self.update(expired: true)
      end
      return nil
    end
    ActiveRecord::Base.transaction do
      self.update(
        demo: encode_demo(parse_demo(replay)),
        expired: false
      )
    end
  rescue => e
    if SHOW_ERRORS
      err("error parsing demo with id #{replay_id}: #{e}")
    end
    return nil
  end
end
