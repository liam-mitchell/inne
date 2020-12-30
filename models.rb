# coding: utf-8
require 'active_record'
require 'net/http'
require 'chunky_png' # for screenshot generation
include ChunkyPNG::Color

RETRIES         = 50    # redownload retries until we move on to the next level
SHOW_ERRORS     = false # log common error messages
LOG_SQL         = false # log _all_ SQL queries (for debugging)
BENCHMARK       = false  # benchmark and log functions (for optimization)
INVALID_RESP    = '-1337'
DEFAULT_TYPES   = ['Level', 'Episode']
DISCORD_LIMIT   = 2000

SCORE_PADDING   =  0    #         fixed    padding, 0 for no fixed padding
DEFAULT_PADDING = 15    # default variable padding, never make 0
MAX_PADDING     = 15    # max     variable padding, 0 for no maximum
TRUNCATE_NAME   = true  # truncate name when it exceeds the maximum padding

USERLEVEL_REPORT_SIZE = 500
ActiveRecord::Base.logger = Logger.new(STDOUT) if LOG_SQL

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
  "VexatiousCheff",
  "vex",
  "DBYT3"
]

# Problematic hackers? We get rid of them by banning their user IDs
IGNORED_IDS = [
  115572, # Mishu
  201322, # dimitry008
  146275, # Puce
  253161, # Chara
  253072, # test8378
  221472, # VexatiousCheff / vex
  276273  # DBYT3
]

# Individually patched runs from legitimate players because they were done
# with older versions of levels and the scores are now incorrect.
# @params: minimum replay id where legit scores start, score adjustment required
PATCH_RUNS = {
  :episode => {
    182 => [695142, -42], # S-C-12
    217 => [1165074, -8]  # S-C-19
  },
  :level => {
    910  => [286360, -42], # S-C-12-00
    1089 => [225710,  -8]  # S-C-19-04
  },
  :story => {
  },
  :userlevel => {
  }
}

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

def bench(action)
  @t ||= Time.now
  @total ||= 0
  @step ||= 0
  case action
  when :start
    @step = 0
    @total = 0
    @t = Time.now
  when :step
    @step += 1
    int = Time.now - @t
    @total += int
    @t = Time.now
    log("Benchmark #{@step}: #{"%.3fms" % (int * 1000)} (Total: #{"%.3fms" % (@total * 1000)}).")
  end
end

def format_string(str, padding = DEFAULT_PADDING)
  if SCORE_PADDING > 0 # FIXED padding mode
    "%-#{"%d" % [SCORE_PADDING]}s" % [str]
  else                 # VARIABLE padding mode
    if MAX_PADDING > 0   # maximum padding supplied
      if padding > 0       # valid padding
        if padding <= MAX_PADDING 
          "%-#{"%d" % [padding]}s" % [str]
        else
          "%-#{"%d" % [MAX_PADDING]}s" % [TRUNCATE_NAME ? str.slice(0, MAX_PADDING) : str]
        end
      else                 # invalid padding
        "%-#{"%d" % [DEFAULT_PADDING]}s" % [str]
      end
    else                 # maximum padding not supplied
      if padding > 0       # valid padding
        "%-#{"%d" % [padding]}s" % [str]
      else                 # invalid padding
        "%-#{"%d" % [DEFAULT_PADDING]}s" % [str]
      end
    end
  end
end

# sometimes we need to make sure there's exactly one valid type
def ensure_type(type)
  (type.nil? || type.is_a?(Array)) ? Level : type
end

# find the optimal score / amount of whatever rankings or stat
def find_max_type(rank, type, tabs)
  case rank
  when :points
    (type == Userlevel || tabs.empty? ? type : type.where(tab: tabs)).count * 20
  when :avg_points
    20
  when :avg_rank
    0
  when :maxable
    20
  when :clean
    0.0
  when :score
    query = type == Userlevel ? UserlevelScore.where(rank: 0) : Score.where(highscoreable_type: type.to_s, rank: 0)
    query = query.where(tab: tabs) if !tabs.empty? && type != Userlevel
    query = query.sum(:score)
    query = query.to_f / 60.0 if type == Userlevel
    query
  else
    (type == Userlevel || tabs.empty? ? type : type.where(tab: tabs)).count
  end
end

def find_max(rank, types, tabs)
  types = [Level, Episode] if types.nil?
  maxes = [types].flatten.map{ |t| find_max_type(rank, t, tabs) }
  [:avg_points, :avg_rank, :maxable].include?(rank) ? maxes.first : maxes.sum
end

def round_score(score)
  (score * 60).round / 60.0
end

module HighScore

  def self.format_rank(rank)
    "#{rank < 10 ? '0' : ''}#{rank}"
  end

  # everything in the "spreads" and "ties" functions has been carefully
  # benchmarked so, though unelegant, it's the most efficient set of
  # sql queries
  def self.spreads(n, type, tabs, small = false, player_id = nil)
    type = ensure_type(type)
    bench(:start) if BENCHMARK
    # retrieve player's 0ths if necessary
    if !player_id.nil?
      ids = Score.where(highscoreable_type: type.to_s, rank: 0, player_id: player_id)
      ids = ids.where(tab: tabs) if !tabs.empty?
      ids = ids.pluck('highscoreable_id')
    end
    # retrieve required scores and compute spreads
    ret1 = Score.where(highscoreable_type: type.to_s, rank: 0)
    ret1 = ret1.where(tab: tabs) if !tabs.empty?
    ret1 = ret1.where(highscoreable_id: ids) if !player_id.nil?
    ret1 = ret1.pluck(:highscoreable_id, :score).to_h
    ret2 = Score.where(highscoreable_type: type.to_s, rank: n)
    ret2 = ret2.where(tab: tabs) if !tabs.empty?
    ret2 = ret2.where(highscoreable_id: ids) if !player_id.nil?
    ret2 = ret2.pluck(:highscoreable_id, :score).to_h
    ret = ret2.map{ |id, s| [id, ret1[id] - s] }
              .sort_by{ |id, s| small ? s : -s }
              .take(NUM_ENTRIES)
              .to_h
    # retrieve level names
    lnames = type.where(id: ret.keys)
                 .pluck(:id, :name)
                 .to_h
    # retrieve player names
    pnames = Score.where(highscoreable_type: type.to_s, highscoreable_id: ret.keys, rank: 0)
                  .joins("INNER JOIN players ON players.id = scores.player_id")
                  .pluck('scores.highscoreable_id', 'players.name', 'players.display_name')
                  .map{ |a, b, c| [a, [b, c]] }
                  .to_h
    ret = ret.map{ |id, s| [lnames[id], s, pnames[id][1].nil? ? pnames[id][0] : pnames[id][1]] }
    bench(:step) if BENCHMARK
    ret
  end

  def self.ties(type, tabs, player_id = nil, maxed = false)
    type = ensure_type(type)
    bench(:start) if BENCHMARK
    # retrieve most tied for 0th leves
    ret = Score.where(highscoreable_type: type.to_s, tied_rank: 0)
    ret = ret.where(tab: tabs) if !tabs.empty?
    ret = ret.group(:highscoreable_id)
             .order(!maxed ? 'count(id) desc' : '', :highscoreable_id)
             .having('count(id) >= 3')
             .having(!player_id.nil? ? 'amount = 0' : '')
             .pluck('highscoreable_id', 'count(id)', !player_id.nil? ? "count(if(player_id = #{player_id}, player_id, NULL)) AS amount" : '1')
             .map{ |s| s[0..1] }
             .to_h
    # retrieve total score counts for each level (to compare against the tie count and determine maxes)
    counts = Score.where(highscoreable_type: type.to_s, highscoreable_id: ret.keys)
                  .group(:highscoreable_id)
                  .order('count(id) desc')
                  .count(:id)
    # retrieve player names owning the 0ths on said level
    pnames = Score.where(highscoreable_type: type.to_s, highscoreable_id: ret.keys, rank: 0)
                  .joins("INNER JOIN players ON players.id = scores.player_id")
                  .pluck('scores.highscoreable_id', 'players.name', 'players.display_name')
                  .map{ |a, b, c| [a, [b, c]] }
                  .to_h
    # retrieve level names
    lnames = type.where(id: ret.keys)
                 .pluck(:id, :name)
                 .to_h
    ret = ret.map{ |id, c| [lnames[id], c, counts[id], pnames[id][1].nil? ? pnames[id][0] : pnames[id][1]] }
    bench(:step) if BENCHMARK
    ret
  end

  def scores_uri(steam_id)
    klass = self.class == Userlevel ? "level" : self.class.to_s.downcase
    URI.parse("https://dojo.nplusplus.ninja/prod/steam/get_scores?steam_id=#{steam_id}&steam_auth=&#{klass}_id=#{self.id.to_s}")
  end

  def replay_uri(steam_id, replay_id)
    qt = [Level, Userlevel].include?(self.class) ? 0 : (self.class == Episode ? 1 : 4)
    URI.parse("https://dojo.nplusplus.ninja/prod/steam/get_replay?steam_id=#{steam_id}&steam_auth=&replay_id=#{replay_id}&qt=#{qt}")
  end

  def get_scores
    initial_id = get_last_steam_id
    attempts ||= 0
    response = Net::HTTP.get_response(scores_uri(initial_id))
    while response.body == INVALID_RESP
      update_last_steam_id
      break if get_last_steam_id == initial_id
      response = Net::HTTP.get_response(scores_uri(get_last_steam_id))
    end
    return nil if response.body == INVALID_RESP
    raise "502 Bad Gateway" if response.code.to_i == 502
    correct_ties(clean_scores(JSON.parse(response.body)['scores']))
  rescue => e
    if (attempts += 1) < RETRIES
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
    response = Net::HTTP.get_response(replay_uri(initial_id, replay_id))
    while response.body == INVALID_RESP
      update_last_steam_id
      break if get_last_steam_id == initial_id
      response = Net::HTTP.get_response(replay_uri(get_last_steam_id, replay_id))
    end
    return nil if response.body == INVALID_RESP
    raise "502 Bad Gateway" if response.code.to_i == 502
    response.body
  rescue => e
    if SHOW_ERRORS
      err("error getting replay with id #{replay_id}: #{e}")
    end
    retry
  end

  # Remove hackers and cheaters both by implementing the ignore lists and the score thresholds.
  def clean_scores(boards)
    # Remove potential duplicates
    boards.uniq!{ |s| s['user_name'] }

    # Compute score upper limit
    if self.class == Userlevel
      limit = 2 ** 32 - 1 # No limit
    else
      limit = TABS[self.class.to_s].map{ |k, v| v[1] }.max
      TABS[self.class.to_s].each{ |k, v| if v[0].include?(self.id) then limit = v[1]; break end  }
    end

    # Filter out cheated/hacked runs
    boards.reject!{ |s|
      IGNORED_PLAYERS.include?(s['user_name']) || IGNORED_IDS.include?(s['user_id']) || s['score'] / 1000.0 >= limit
    }

    # Patch old incorrect runs
    k = self.class.to_s.downcase.to_sym
    if PATCH_RUNS[k].key?(self.id)
      boards.each{ |s|
        entry = PATCH_RUNS[k][self.id]
        s['score'] += 1000 * entry[1] if s['replay_id'] <= entry[0]
      }
    end

    boards
  rescue
    boards
  end

  def save_scores(updated)
    ActiveRecord::Base.transaction do
      updated.each_with_index do |score, i|
        # Compute values, userlevels have some differences
        player = (self.class == Userlevel ? UserlevelPlayer : Player).find_or_create_by(metanet_id: score['user_id'])
        player.update(name: score['user_name'].force_encoding('UTF-8'))
        scoretime = score['score'] / 1000.0
        scoretime = (scoretime * 60.0).round if self.class == Userlevel
        # Update common values
        scores.find_or_create_by(rank: i).update(
          score:     scoretime,
          replay_id: score['replay_id'].to_i,
          player:    player,
          tied_rank: updated.find_index { |s| s['score'] == score['score'] }
        )
        # Update class-specific values
        scores.find_by(rank: i).update(tab: self.tab) if self.class != Userlevel
        # Update the archive if the run is new
        if self.class != Userlevel && Archive.find_by(replay_id: score['replay_id'], highscoreable_type: self.class.to_s).nil?
          # Update archive entry
          ar = Archive.create(
            replay_id:     score['replay_id'].to_i,
            player:        Player.find_by(metanet_id: score['user_id']),
            highscoreable: self,
            score:         (score['score'] * 60.0 / 1000.0).round,
            metanet_id:    score['user_id'].to_i, # future-proof the db
            date:          Time.now,
            tab:           self.tab
          )
          # Update demo entry
          demo = Demo.find_or_create_by(id: ar.id)
          demo.update(replay_id: ar.replay_id, htype: Demo.htypes[ar.highscoreable_type.to_s.downcase])
          demo.update_demo
        end
      end
      self.update(last_update: Time.now) if self.class == Userlevel
      self.update(scored:       true)    if self.class == Userlevel && updated.size > 0
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
  belongs_to :episode
  enum tab: [:SI, :S, :SU, :SL, :SS, :SS2]

  def format_name
    "#{longname} (#{name})"
  end
end

class Episode < ActiveRecord::Base
  include HighScore
  has_many :scores, as: :highscoreable
  has_many :videos, as: :highscoreable
  has_many :levels
  enum tab: [:SI, :S, :SU, :SL, :SS, :SS2]

  def self.cleanliness(tabs, rank = 0)
    bench(:start) if BENCHMARK
    query = !tabs.empty? ? Score.where(tab: tabs) : Score
    # retrieve level 0th sums
    lvls = query.where(highscoreable_type: 'Level', rank: 0)
                .joins('INNER JOIN levels ON levels.id = scores.highscoreable_id')
                .group('levels.episode_id')
                .sum(:score)
    # retrieve episode names
    epis = self.pluck(:id, :name).to_h
    # retrieve episode 0th scores
    ret = query.where(highscoreable_type: 'Episode', rank: 0)
               .joins('INNER JOIN episodes ON episodes.id = scores.highscoreable_id')
               .joins('INNER JOIN players ON players.id = scores.player_id')
               .pluck('episodes.id', 'scores.score', 'players.name')
               .map{ |e, s, n| [epis[e], round_score(lvls[e] - s - 360), n] }
    bench(:step) if BENCHMARK
    ret
  end

  def self.ownages(tabs)
    bench(:start) if BENCHMARK
    query = !tabs.empty? ? Score.where(tab: tabs) : Score
    # retrieve episodes with all 5 levels owned by the same person
    epis = query.where(highscoreable_type: 'Level', rank: 0)
                .joins('INNER JOIN levels ON levels.id = scores.highscoreable_id')
                .group('levels.episode_id')
                .having('cnt = 1')
                .pluck('levels.episode_id', 'MIN(scores.player_id)', 'COUNT(DISTINCT scores.player_id) AS cnt')
                .map{ |e, p, c| [e, p] }
                .to_h
    # retrieve respective episode 0ths
    zeroes = query.where(highscoreable_type: 'Episode', highscoreable_id: epis.keys, rank: 0)
                  .joins('INNER JOIN players ON players.id = scores.player_id')
                  .pluck('scores.highscoreable_id', 'players.id')
                  .to_h
    # retrieve episode names
    enames = Episode.where(id: epis.keys)
                    .pluck(:id, :name)
                    .to_h
    # retrieve player names
    pnames = Player.where(id: epis.values)
                   .pluck(:id, :name, :display_name)
                   .map{ |a, b, c| [a, [b, c]] }
                   .to_h
    # keep only matches between the previous 2 result sets to obtain true ownages
    ret = epis.reject{ |e, p| p != zeroes[e] }
              .sort_by{ |e, p| e }
              .map{ |e, p| [enames[e], pnames[p][1].nil? ? pnames[p][0] : pnames[p][1]] }
    bench(:step) if BENCHMARK
    ret
  end

  def format_name
    "#{name}"
  end

  def cleanliness(rank = 0)
    bench(:start) if BENCHMARK
    ret = [name, Score.where(highscoreable: levels, rank: 0).sum(:score) - scores[rank].score - 360, scores[rank].player.name]
    bench(:step) if BENCHMARK
    ret
  end

  def ownage
    bench(:start) if BENCHMARK
    owner = scores[0].player
    lvls = Score.where(highscoreable: levels, rank: 0)
                .joins('INNER JOIN players ON players.id = scores.player_id')
                .count("if(players.id = #{owner.id}, 1, NULL)")
    ret = [name, lvls == 5, owner.name]
    bench(:step) if BENCHMARK
    ret
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
#  default_scope -> { select("scores.*, score * 1.000 as score")} # Ensure 3 correct decimal places
  enum tab:  [ :SI, :S, :SU, :SL, :SS, :SS2 ]

  # Alternative method to perform rankings which outperforms the Player approach
  # since we leave all the heavy lifting to the SQL interface instead of Ruby.
  def self.rank(ranking, type, tabs, ties = false, n = 0, full = false)
    type = Level if ranking == :avg_lead && (type.nil? || type.is_a?(Array)) # avg lead only works with 1 type
    scores = self.where(highscoreable_type: type.nil? ? DEFAULT_TYPES : type.to_s)
    scores = scores.where(tab: tabs) if !tabs.empty?
    bench(:start) if BENCHMARK

    case ranking
    when :rank
      scores = scores.where("#{ties ? "tied_rank" : "rank"} <= #{n}")
                     .group(:player_id)
                     .order('count_id desc')
                     .count(:id)
    when :tied_rank
      scores_w  = scores.where("tied_rank <= #{n}")
                        .group(:player_id)
                        .order('count_id desc')
                        .count(:id)
      scores_wo = scores.where("rank <= #{n}")
                        .group(:player_id)
                        .order('count_id desc')
                        .count(:id)
      scores = scores_w.map{ |id, count| [id, count - scores_wo[id].to_i] }
                       .sort_by{ |id, c| -c }
    when :points
      scores = scores.group(:player_id)
                     .order("sum(#{ties ? "20 - tied_rank" : "20 - rank"}) desc")
                     .sum(ties ? "20 - tied_rank" : "20 - rank")
    when :avg_points
      scores = scores.select("count(player_id)")
                     .group(:player_id)
                     .having("count(player_id) >= #{MIN_SCORES}")
                     .order("avg(#{ties ? "20 - tied_rank" : "20 - rank"}) desc")
                     .average(ties ? "20 - tied_rank" : "20 - rank")
    when :avg_rank
      scores = scores.select("count(player_id)")
                     .group(:player_id)
                     .having("count(player_id) >= #{MIN_SCORES}")
                     .order("avg(#{ties ? "tied_rank" : "rank"})")
                     .average(ties ? "tied_rank" : "rank")
    when :avg_lead
      scores = scores.where(rank: [0, 1])
                     .pluck(:player_id, :highscoreable_id, :score)
                     .group_by{ |s| s[1] }
                     .map{ |h, s| [s[0][0], s[0][2] - s[1][2]] }
                     .group_by{ |s| s[0] }
                     .map{ |p, s| [p, s.map(&:last).sum / s.map(&:last).count] }
                     .sort_by{ |p, s| -s }
    when :score
      scores = scores.group(:player_id)
                     .order("sum(score) desc")
                     .sum(:score)
                     .map{ |id, c| [id, round_score(c)] }
    end

    scores = scores.take(NUM_ENTRIES) if !full
    # find all players in advance (better performant)
    players = Player.where(id: scores.map(&:first))
                    .map{ |p| [p.id, p] }
                    .to_h
    ret = scores.map{ |p, c| [players[p], c] }
                .reject{ |p, c| c <= 0  }
    bench(:step) if BENCHMARK
    ret
  end

  def self.total_scores(type, tabs, secrets)
    bench(:start) if BENCHMARK
    tabs = (tabs.empty? ? [:SI, :S, :SL, :SU, :SS, :SS2] : tabs)
    tabs = (secrets ? tabs : tabs - [:SS, :SS2])
    ret = self.where(highscoreable_type: type.to_s, tab: tabs, rank: 0)
              .pluck('SUM(score)', 'COUNT(score)')
              .map{ |score, count| [round_score(score.to_f), count.to_i] }
    bench(:step) if BENCHMARK
    ret.first
  end

  def spread
    highscoreable.scores.find_by(rank: 0).score - score
  end

  def demo
    Demo.find_by(replay_id: replay_id, htype: Demo.htypes[highscoreable.class.to_s.downcase.to_sym])
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

  # Deprecated since it's slower, see Score::rank
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

  def print_name
    user = User.where(playername: name).where.not(displayname: nil)
    user.empty? ? name : user.first.displayname
  end

  def format_name(padding = DEFAULT_PADDING)
    format_string(print_name, padding)
  end

  def scores_by_type_and_tabs(type, tabs, include = nil)
    ret = scores.where(highscoreable_type: type.nil? ? DEFAULT_TYPES : type.to_s)
    ret = ret.where(tab: tabs) if !tabs.empty?
    case include
    when :scores
      ret.includes(highscoreable: [:scores])
    when :name
      ret.includes(:highscoreable)
    else
      ret
    end
  end

  def top_ns(n, type, tabs, ties)
    scores_by_type_and_tabs(type, tabs).where("#{ties ? "tied_rank" : "rank"} < #{n}")
  end

  def top_n_count(n, type, tabs, ties)
    top_ns(n, type, tabs, ties).count
  end

  def scores_by_rank(type, tabs)
    bench(:start) if BENCHMARK
    ret = Array.new(20, [])
    scores_by_type_and_tabs(type, tabs).group_by(&:rank).sort_by(&:first).each { |rank, scores| ret[rank] = scores }
    bench(:step) if BENCHMARK
    ret
  end

  def score_counts(tabs, ties)
    bench(:start) if BENCHMARK
    counts = {
      levels:   scores_by_type_and_tabs(Level,   tabs).group(ties ? :tied_rank : :rank).order(ties ? :tied_rank : :rank).count(:id),
      episodes: scores_by_type_and_tabs(Episode, tabs).group(ties ? :tied_rank : :rank).order(ties ? :tied_rank : :rank).count(:id),
      stories:  scores_by_type_and_tabs(Story,   tabs).group(ties ? :tied_rank : :rank).order(ties ? :tied_rank : :rank).count(:id)
    }
    bench(:step) if BENCHMARK
    counts
  end

  def missing_top_ns(type, tabs, n, ties)
    type = [Level, Episode] if type.nil?
    bench(:start) if BENCHMARK
    scores = [type].flatten.map{ |t|
      ids = top_ns(n, t, tabs, ties).pluck(:highscoreable_id)
      (tabs.empty? ? t : t.where(tab: tabs)).where.not(id: ids).pluck(:name)
    }.flatten
#    scores = (tabs.empty? ? type : type.where(tab: tabs)).where.not(id: ids).pluck(:name)
    bench(:step) if BENCHMARK
    scores
  end

  def improvable_scores(type, tabs, n)
    type = ensure_type(type) # only works for a single type
    bench(:start) if BENCHMARK
    ids = scores_by_type_and_tabs(type, tabs).pluck(:highscoreable_id, :score).to_h
    ret = Score.where(highscoreable_type: type.to_s, highscoreable_id: ids.keys, rank: 0)
    ret = ret.pluck(:highscoreable_id, :score)
             .map{ |id, s| [id, s - ids[id]] }
             .sort_by{ |s| -s[1] }
             .take(n)
             .map{ |id, s| [type.find(id).name, s] }
    bench(:step) if BENCHMARK
    ret
  end

  def points(type, tabs)
    bench(:start) if BENCHMARK
    points = scores_by_type_and_tabs(type, tabs).sum('20 - rank')
    bench(:step) if BENCHMARK
    points
  end

  def average_points(type, tabs)
    bench(:start) if BENCHMARK
    scores = scores_by_type_and_tabs(type, tabs).average('20 - rank')
    bench(:step) if BENCHMARK
    scores
  end

  def total_score(type, tabs)
    bench(:start) if BENCHMARK
    scores = scores_by_type_and_tabs(type, tabs).sum(:score)
    bench(:step) if BENCHMARK
    scores
  end

  def average_lead(type, tabs)
    type = ensure_type(type) # only works for a single type
    bench(:start) if BENCHMARK

    ids = top_ns(1, type, tabs, false).pluck('highscoreable_id')
    ret = Score.where(highscoreable_type: type.to_s, highscoreable_id: ids, rank: [0, 1])
    ret = ret.where(tab: tabs) if !tabs.empty?
    ret = ret.pluck(:highscoreable_id, :score)
    count = ret.count / 2
    return 0 if count == 0
    ret = ret.group_by(&:first).map{ |id, sc| (sc[0][1] - sc[1][1]).abs }.sum / count
## alternative way, faster when the player has many 0ths but slower otherwise (usual outcome)
#    ret = Score.where(highscoreable_type: type.to_s, rank: [0, 1])
#    ret = ret.where(tab: tabs) if !tabs.empty?
#    ret = ret.pluck(:player_id, :highscoreable_id, :score)
#             .group_by{ |s| s[1] }
#             .map{ |h, s| s[0][2] - s[1][2] if s[0][0] == id }
#             .compact
#    count = ret.count
#    return 0 if count == 0
#    ret = ret.sum / count

    bench(:step) if BENCHMARK
    ret
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

  def self.compose(rankings, type, tab, rank, ties, time)
    rankings.select { |r| r[1] > 0 }.map do |r|
      {
        highscoreable_type: type.to_s,
        rank:               rank,
        ties:               ties,
        tab:                tab,
        player:             r[0],
        count:              r[1],
        metanet_id:         r[0].metanet_id,
        timestamp:          time
      }
    end
  end
end

class PointsHistory < ActiveRecord::Base
  belongs_to :player
  enum tab: [:SI, :S, :SU, :SL, :SS, :SS2]

  def self.compose(rankings, type, tab, time)
    rankings.select { |r| r[1] > 0 }.map do |r|
      {
        timestamp:          time,
        tab:                tab,
        highscoreable_type: type.to_s,
        player:             r[0],
        metanet_id:         r[0].metanet_id,
        points:             r[1]
      }
    end
  end
end

class TotalScoreHistory < ActiveRecord::Base
  belongs_to :player
  enum tab: [:SI, :S, :SU, :SL, :SS, :SS2]

  def self.compose(rankings, type, tab, time)
    rankings.select { |r| r[1] > 0 }.map do |r|
      {
        timestamp:          time,
        tab:                tab,
        highscoreable_type: type.to_s,
        player:             r[0],
        metanet_id:         r[0].metanet_id,
        score:              r[1]
      }
    end
  end
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
  enum tab: [:SI, :S, :SU, :SL, :SS, :SS2]

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
    Demo.find(self.d).demo
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
  enum htype: [:level, :episode, :story]

  def score
    Archive.find(self.id)
  end

  def qt
    case htype.to_sym
    when :level
      0
    when :episode
      1
    when :story
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
    while response.body == INVALID_RESP
      update_last_steam_id
      break if get_last_steam_id == initial_id
      response = Net::HTTP.get_response(demo_uri(get_last_steam_id))
    end
    return 1 if response.code.to_i == 200 && response.body.empty? # replay does not exist
    return nil if response.body == INVALID_RESP
    raise "502 Bad Gateway" if response.code.to_i == 502
    response.body
  rescue => e
    if (attempts += 1) < RETRIES
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
    header = {level: 0, episode:  4, story:   8}[htype.to_sym]
    offset = {level: 0, episode: 24, story: 108}[htype.to_sym]
    count  = {level: 1, episode:  5, story:  25}[htype.to_sym]

    lengths = (0..count - 1).map{ |d| _unpack(data[header + 4 * d..header + 4 * (d + 1) - 1]) }
    lengths = [_unpack(data[1..4])] if htype.to_sym == :level
    (0..count - 1).map{ |d|
      offset += lengths[d - 1] unless d == 0
      data[offset..offset + lengths[d] - 1][30..-1]
    }
  end

  def encode_demo(replay)
    replay = [replay] if replay.class == String
    Zlib::Deflate.deflate(replay.join('&'), 9)
  end

  def decode_demo
    return nil if demo.nil?
    demos = Zlib::Inflate.inflate(demo).split('&')
    return (demos.size == 1 ? demos.first.scan(/./m).map(&:ord) : demos.map{ |d| d.scan(/./m).map(&:ord) })
  end

  def update_demo
    replay = get_demo
    return nil if replay.nil? # replay was not fetched successfully
    if replay == 1 # replay does not exist
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
