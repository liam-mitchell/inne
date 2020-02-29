# coding: utf-8
require 'active_record'
require 'net/http'
require 'chunky_png' # for screenshot generation
include ChunkyPNG::Color

SCORE_PADDING =    0 #         fixed    padding, 0 for no fixed padding
DEFAULT_PADDING = 15 # default variable padding, never make 0
MAX_PADDING =     15 # max     variable padding, 0 for no maximum
TRUNCATE_NAME = true # truncate name when it exceeds the maximum padding

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
  "Puςe",
  "Floof The Goof",
  "Prismo",
  "Mishu"
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
    ties = {}
    scores = tabs.empty? ? type.all : type.where(tab: tabs)

    scores.each do |elem|
      tie_count = elem.tie_count
      if !tie_count.nil? && tie_count >= 3
        ties[elem] = tie_count
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
    response = Net::HTTP.get(scores_uri(initial_id))
    while response == '-1337'
      update_last_steam_id
      break if get_last_steam_id == initial_id
      response = Net::HTTP.get(scores_uri(get_last_steam_id))
    end
    return nil if response == '-1337'
    correct_ties(JSON.parse(response)['scores'])
  rescue => e
    # im getting tired of seeing this error, will uncomment if needed
    #err("error getting scores for #{self.class.to_s.downcase} with id #{self.id.to_s}: #{e}")
    retry
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
    err("error getting replay with id #{replay_id}: #{e}")
    retry
  end

  def save_scores(updated)
    updated = updated.select { |score| !IGNORED_PLAYERS.include?(score['user_name']) }.uniq { |score| score['user_name'] }

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

  def update_scores
    updated = get_scores

    if updated.nil?
      # TODO make this use err()
      STDERR.puts "[WARNING] [#{Time.now}] failed to retrieve scores from #{scores_uri(get_last_steam_id)}"
      return
    end

    save_scores(updated)
  end

  def get_replay_info(rank)
    updated = get_scores

    if updated.nil?
      # TODO make this use err()
      STDERR.puts "[WARNING] [#{Time.now}] failed to retrieve replay info from #{scores_uri(get_last_steam_id)}"
      return
    end

    updated.select { |score| !IGNORED_PLAYERS.include?(score['user_name']) }.uniq { |score| score['user_name'] }[rank]
  end

  # Replay data format: Unknown (4B), replay ID (4B), level ID (4B), user ID (4B) and demo data compressed with Zlib.
  # Demo data format: Unknown (1B), data length (4B), unknown (4B), frame count (4B), level ID (4B), unknown (13B) and actual demo.
  # Demo format: Each byte is one frame, first bit is jump, second is right and third is left. Also, suicide is 0C.
  # Note: The first frame is fictional and must be ignored.
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

  def cleanliness
    [name, Level.where("UPPER(name) LIKE ?", name.upcase + '%').map{ |l| l.scores[0].score }.sum - scores[0].score - 360]
  end

  def ownage
    owner = scores[0].player.name
    [name, Level.where("UPPER(name) LIKE ?", name.upcase + '%').map{ |l| l.scores[0].player.name == owner }.count(true) == 5, owner]
  end
end

class Score < ActiveRecord::Base
  belongs_to :player
  belongs_to :highscoreable, polymorphic: true
  belongs_to :level, -> { where(scores: {highscoreable_type: 'Level'}) }, foreign_key: 'highscoreable_id'
  belongs_to :episode, -> { where(scores: {highscoreable_type: 'Episode'}) }, foreign_key: 'highscoreable_id'

  def self.total_scores(type, tabs, secrets)
    tabs = (tabs.empty? ? [:SI, :S, :SL, :SU, :SS, :SS2] : tabs)
    tabs = (secrets ? tabs : tabs - [:SS, :SS2])
    query = self.where(rank: 0, highscoreable_type: type.to_s)
    result = (query.includes(:level).where(levels: {tab: tabs}) + query.includes(:episode).where(episodes: {tab: tabs})).map{ |s| s.score }
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

class Player < ActiveRecord::Base
  has_many :scores
  has_many :rank_histories
  has_many :points_histories
  has_many :total_score_histories
  has_one :user

  def self.rankings(&block)
    players = Player.includes(:scores).all

    players.map { |p| [p, yield(p)] }
      .sort_by { |a| -a[1] }
  end

  def self.histories(type, attrs, column)
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

class Userlevel < ActiveRecord::Base
  # available fields: id,  author, author_id, title, favs, date, tile_data (renamed as tiles), object_data (renamed as objects)

  # 'pref' is the drawing preference when for overlaps, the lower the better
  # 'att' is the number of attributes they have in the old format (in the new one it's always 5)
  # 'old' is the ID in the old format, '-1' if it didn't exist
  # 'pal' is the index at which the colors of the object start in the palette image
  OBJECTS = {
    0x00 => {name: 'ninja',              pref:  4, att: 2, old:  0, pal:  6},
    0x01 => {name: 'mine',               pref: 22, att: 2, old:  1, pal: 10},
    0x02 => {name: 'gold',               pref: 21, att: 2, old:  2, pal: 14},
    0x03 => {name: 'exit',               pref: 25, att: 4, old:  3, pal: 17},
    0x04 => {name: 'exit switch',        pref: 20, att: 0, old: -1, pal: 25},
    0x05 => {name: 'regular door',       pref: 19, att: 3, old:  4, pal: 30},
    0x06 => {name: 'locked door',        pref: 28, att: 5, old:  5, pal: 31},
    0x07 => {name: 'locked door switch', pref: 27, att: 0, old: -1, pal: 33},
    0x08 => {name: 'trap door',          pref: 29, att: 5, old:  6, pal: 39},
    0x09 => {name: 'trap door switch',   pref: 26, att: 0, old: -1, pal: 41},
    0x0A => {name: 'launch pad',         pref: 18, att: 3, old:  7, pal: 47},
    0x0B => {name: 'one-way platform',   pref: 24, att: 3, old:  8, pal: 49},
    0x0C => {name: 'chaingun drone',     pref: 16, att: 4, old:  9, pal: 51},
    0x0D => {name: 'laser drone',        pref: 17, att: 4, old: 10, pal: 53},
    0x0E => {name: 'zap drone',          pref: 15, att: 4, old: 11, pal: 57},
    0x0F => {name: 'chase drone',        pref: 14, att: 4, old: 12, pal: 59},
    0x10 => {name: 'floor guard',        pref: 13, att: 2, old: 13, pal: 61},
    0x11 => {name: 'bounce block',       pref:  3, att: 2, old: 14, pal: 63},
    0x12 => {name: 'rocket',             pref:  8, att: 2, old: 15, pal: 65},
    0x13 => {name: 'gauss turret',       pref:  9, att: 2, old: 16, pal: 69},
    0x14 => {name: 'thwump',             pref:  6, att: 3, old: 17, pal: 74},
    0x15 => {name: 'toggle mine',        pref: 23, att: 2, old: 18, pal: 12},
    0x16 => {name: 'evil ninja',         pref:  5, att: 2, old: 19, pal: 77},
    0x17 => {name: 'laser turret',       pref:  7, att: 4, old: 20, pal: 79},
    0x18 => {name: 'boost pad',          pref:  1, att: 2, old: 21, pal: 81},
    0x19 => {name: 'deathball',          pref: 10, att: 2, old: 22, pal: 83},
    0x1A => {name: 'micro drone',        pref: 12, att: 4, old: 23, pal: 57},
    0x1B => {name: 'alt deathball',      pref: 11, att: 2, old: 24, pal: 86},
    0x1C => {name: 'shove thwump',       pref:  2, att: 2, old: 25, pal: 88}
  }
  FIXED_OBJECTS = [0, 1, 2, 3, 4, 7, 9, 16, 17, 18, 19, 21, 22, 24, 25, 28]
  THEMES = ["acid", "airline", "argon", "autumn", "BASIC", "berry", "birthday cake",
  "bloodmoon", "blueprint", "bordeaux", "brink", "cacao", "champagne", "chemical",
  "chococherry", "classic", "clean", "concrete", "console", "cowboy", "dagobah",
  "debugger", "delicate", "desert world", "disassembly", "dorado", "dusk", "elephant",
  "epaper", "epaper invert CUT", "evening", "F7200", "florist", "formal", "galactic",
  "gatecrasher", "gothmode", "grapefrukt", "grappa", "gunmetal", "hazard", "heirloom",
  "holosphere", "hope", "hot", "hyperspace", "ice world", "incorporated", "infographic",
  "invert", "jaune", "juicy", "kicks", "lab", "lava world", "lemonade", "lichen",
  "lightcycle", "line CUT", "m", "machine", "metoro", "midnight", "minus", "mir",
  "mono", "moonbase", "mustard", "mute", "nemk", "neptune", "neutrality", "noctis",
  "oceanographer", "okinami", "orbit", "pale", "papier CUT", "papier invert", "party",
  "petal", "PICO-8", "pinku", "plus", "porphyrous", "poseidon", "powder", "pulse",
  "pumpkin", "QDUST", "quench", "regal", "replicant", "retro", "rust", "sakura",
  "shift", "shock", "simulator", "sinister", "solarized dark", "solarized light",
  "starfighter", "sunset", "supernavy", "synergy", "talisman", "toothpaste", "toxin",
  "TR-808", "tycho CUT", "vasquez", "vectrex", "vintage", "virtual", "vivid", "void",
  "waka", "witchy", "wizard", "wyvern", "xenon", "yeti"]
  PALETTE = ChunkyPNG::Image.from_file('images/palette.png')
  BORDERS = "100FF87E1781E0FC3F03C0FC3F03C0FC3F03C078370388FC7F87C0EC1E01C1FE3F13E"
  ROWS = 23
  COLUMNS = 42
  DIM = 44
  WIDTH = DIM * (COLUMNS + 2)
  HEIGHT = DIM * (ROWS + 2)

  def self.levels_uri(steam_id, qt = 10, page = 0, mode = 0)
    URI("https://dojo.nplusplus.ninja/prod/steam/query_levels?steam_id=#{steam_id}&steam_auth=&qt=#{qt}&mode=#{mode}&page=#{page}")
  end

  def self.search_uri(steam_id, search, page = 0, mode = 0)
    URI("https://dojo.nplusplus.ninja/prod/steam/search/levels?steam_id=#{steam_id}&steam_auth=&search=#{search}&mode=#{mode}&page=#{page}")
  end

  def self.serial(maps)
    maps.map(&:as_json).map(&:symbolize_keys)
  end

  def self.get_levels(qt = 10, page = 0, mode = 0)
    initial_id = get_last_steam_id
    response = Net::HTTP.get(levels_uri(initial_id, qt, page, mode))
    while response == '-1337'
      update_last_steam_id
      break if get_last_steam_id == initial_id
      response = Net::HTTP.get(levels_uri(get_last_steam_id, qt, page, mode))
    end
    return nil if response == '-1337'
    response
  rescue => e
    err("error querying page nº #{page} of userlevels from category #{qt}: #{e}")
    retry
  end

  def self.get_search(search = "", page = 0, mode = 0)
    initial_id = get_last_steam_id
    response = Net::HTTP.get(search_uri(initial_id, search, page, mode))
    while response == '-1337'
      update_last_steam_id
      break if get_last_steam_id == initial_id
      response = Net::HTTP.get(search_uri(get_last_steam_id, search, page, mode))
    end
    return nil if response == '-1337'
    response
  rescue => e
    err("error searching for userlevels containing \"#{search}\", page nº #{page}: #{e}")
    retry
  end

  # Format of query result: Header (48B) + adjacent map headers (44B each) + adjacent map data blocks (variable length).
  # 1) Header format: Date (16B), map count (4B), page (4B), unknown (4B), category (4B), game mode (4B), unknown (12B).
  # 2) Map header format: Map ID (4B), user ID (4B), author name (16B), # of ++'s (4B), date of publishing (16B).
  # 3) Map data block format: Size of block (4B), # of objects (2B), zlib-compressed map data.
  # Uncompressed map data format: Header (30B) + title (128B) + null (18B) + map data (variable).
  # 1) Header format: Unknown (4B), game mode (4B), unknown (4B), user ID (4B), unknown (14B).
  # 2) Map format: Tile data (966B, 1B per tile), object counts (80B, 2B per object type), objects (variable, 5B per object).
  def self.parse(levels, update = true)
    header = {
      date: format_date(levels[0..15].to_s),
      count: parse_int(levels[16..19]),
      page: parse_int(levels[20..23]),
      category: parse_int(levels[28..31]),
      mode: parse_int(levels[32..35])
    }
    # the regex flag "m" is needed so that the global character "." matches the new line character
    # it was hell to debug this!
    # Note: When parsing user input (map titles and authors), we stop reading at the first null character,
    # for everything after that is usually padding. Then, we remove non-ASCII characters.
    maps = levels[48 .. 48 + 44 * header[:count] - 1].scan(/./m).each_slice(44).to_a.map { |h|
      author = h[8..23].join.split("\x00")[0].to_s.each_byte.map{ |b| (b < 32 || b > 127) ? nil : b.chr }.compact.join.strip
      {
        id: parse_int(h[0..3]),
        author_id: author != "null" ? parse_int(h[4..7]) : -1,
        author: author,
        favs: parse_int(h[24..27]),
        date: format_date(h[28..-1].join)
      }
    }
    i = 0
    offset = 48 + header[:count] * 44
    while i < header[:count]
      len = parse_int(levels[offset..offset + 3])
      maps[i][:object_count] = parse_int(levels[offset + 4..offset + 5])
      map = Zlib::Inflate.inflate(levels[offset + 6..offset + len - 1])
      maps[i][:title] = map[30..157].split("\x00")[0].to_s.each_byte.map{ |b| (b < 32 || b > 127) ? nil : b.chr }.compact.join.strip
      maps[i][:tiles] = map[176..1141].scan(/./m).map{ |b| parse_int(b) }.each_slice(42).to_a
      maps[i][:objects] = map[1222..-1].scan(/./m).map{ |b| parse_int(b) }.each_slice(5).to_a
      offset += len
      i += 1
    end
    result = []
    # Update database
    if update
      ActiveRecord::Base.transaction do
        maps.each{ |map|
          entry = Userlevel.find_or_create_by(id: map[:id])
          entry.update(
            title: map[:title],
            author: map[:author],
            author_id: map[:author_id],
            favs: map[:favs],
            date: map[:date],
            mode: header[:mode],
            tile_data: map[:tiles],
            object_data: map[:objects]
          )
          result << entry
        }
      end
    else
      result = maps
    end
    result
  rescue => e
    nil
  end

  def self.browse(qt = 10, page = 0, mode = 0)
    levels = get_levels(qt, page, mode)
    parse(levels)
  end

  def self.search(search = "", page = 0, mode = 0)
    levels = get_search(search, page, mode)
    parse(levels)
  end

  def self.sort(maps, order)
    fields = { # possible spellings for each field, to be used for sorting or filtering
      :n => ["n", "number"],
      :id => ["id", "map id", "map_id", "level id", "level_id"],
      :title => ["title", "name"],
      :author => ["author", "player", "user"],
      :date => ["date", "time"],
      :favs => ["fav", "favs", "++", "++s", "++'s", "favourite", "favourites"]
    }
    reverse = [:id, :date, :favs] # the order of these fields will be reversed by default
    if !order.nil?
      fields.each{ |k, v|
        if v.include?(order.strip)
          order = k
          break
        end
      }
    else
      order = :n
    end
    if !order.is_a?(Symbol) then order = :n end
    if order != :n then maps = maps.sort_by(&order) end
    if reverse.include?(order) then maps.reverse! end
    maps
  end

  def tiles
    YAML.load(self.tile_data)
  end

  def objects
    YAML.load(self.object_data)
  end

  # Convert an integer into a little endian binary string of 'size' bytes
  def _pack(n, size)
    n.to_s(16).rjust(2 * size, "0").scan(/../).reverse.map{ |b| [b].pack('H*')[0] }.join.force_encoding("ascii-8bit")
  end

  # Generate a file with the usual userlevel format
  def convert
    # HEADER
    data = ("\x00" * 4).force_encoding("ascii-8bit")   # magic number ?
    data << _pack(1230 + 5 * self.objects.size, 4)     # filesize
    data << ("\xFF" * 4).force_encoding("ascii-8bit")  # static data
    data << _pack(self.mode, 4)                        # game mode
    data << ("\x25" + "\x00" * 3 + "\xFF" * 4 + "\x00" * 14).force_encoding("ascii-8bit") # static data
    data << self.title[0..126].ljust(128,"\x00").force_encoding("ascii-8bit") # map title
    data << ("\x00" * 18).force_encoding("ascii-8bit") # static data

    # MAP DATA
    tile_data = self.tiles.flatten.map{ |b| [b.to_s(16).rjust(2,"0")].pack('H*')[0] }.join
    object_counts = ""
    object_data = ""
    OBJECTS.sort_by{ |id, entity| id }.each{ |id, entity|
      if ![7,9].include?(id) # ignore door switches for counting
        object_counts << self.objects.select{ |o| o[0] == id }.size.to_s(16).rjust(4,"0").scan(/../).reverse.map{ |b| [b].pack('H*')[0] }.join
      else
        object_counts << "\x00\x00"
      end
      if ![6,7,8,9].include?(id) # doors must once again be treated differently
        object_data << self.objects.select{ |o| o[0] == id }.map{ |o| o.map{ |b| [b.to_s(16).rjust(2,"0")].pack('H*')[0] }.join }.join
      elsif [6,8].include?(id)
        doors = self.objects.select{ |o| o[0] == id }.map{ |o| o.map{ |b| [b.to_s(16).rjust(2,"0")].pack('H*')[0] }.join }
        switches = self.objects.select{ |o| o[0] == id + 1 }.map{ |o| o.map{ |b| [b.to_s(16).rjust(2,"0")].pack('H*')[0] }.join }
        object_data << doors.zip(switches).flatten.join
      end
    }
    data << (tile_data + object_counts.ljust(80, "\x00") + object_data).force_encoding("ascii-8bit")
    data
  end

  # <-------------------------------------------------------------------------->
  #                           SCREENSHOT GENERATOR
  # <-------------------------------------------------------------------------->

  def coord(n) # transform N++ coordinates into pixel coordinates
    DIM * n.to_f / 4
  end

  def check_dimensions(image, x, y) # ensure image is within limits
    x >= 0 && y >= 0 && x <= WIDTH - image.width && y <= HEIGHT - image.height
  end

  # The following two methods are used for theme generation
  def mask(image, before, after, bg = WHITE, tolerance = 0.5)
    new_image = ChunkyPNG::Image.new(image.width, image.height, TRANSPARENT)
    image.width.times{ |x|
      image.height.times{ |y|
        score = euclidean_distance_rgba(image[x,y], before).to_f / MAX_EUCLIDEAN_DISTANCE_RGBA
        if score < tolerance then new_image[x,y] = ChunkyPNG::Color.compose(after, bg) end
      }
    }
    new_image
  end

  # Generate the image of an object in the specified palette, by painting and combining each layer.
  # Note: "special" indicates that we take the special version of the layers. In practice,
  # this is used because we can't rotate images 45 degrees with this library, so we have a
  # different image for that, which we call special.
  def generate_object(object_id, palette_id, object = true, special = false)
    # Select necessary layers
    parts = Dir.entries("images/#{object ? "object" : "tile"}_layers").select{ |file| file[0..1] == object_id.to_s(16).upcase.rjust(2, "0") }.sort
    parts_normal = parts.select{ |file| file[-6] == "-" }
    parts_special = parts.select{ |file| file[-6] == "s" }
    parts = (!special ? parts_normal : (parts_special.empty? ? parts_normal : parts_special))

    # Paint and combine the layers
    masks = parts.map{ |part| [part[-5], ChunkyPNG::Image.from_file("images/#{object ? "object" : "tile"}_layers/" + part)] }
    images = masks.map{ |mask| mask(mask[1], BLACK, PALETTE[(object ? OBJECTS[object_id][:pal] : 0) + mask[0].to_i, palette_id]) }
    dims = [ [DIM, *images.map{ |i| i.width }].max, [DIM, *images.map{ |i| i.height }].max ]
    output = ChunkyPNG::Image.new(*dims, TRANSPARENT)
    images.each{ |image| output.compose!(image, 0, 0) }
    output
  end

  def screenshot(theme = "vasquez")
    if !THEMES.include?(theme) then theme = "vasquez" end

    # INITIALIZE IMAGES
    tile = [0, 1, 2, 6, 10, 14, 18, 22, 26, 30].map{ |o| [o, generate_object(o, THEMES.index(theme), false)] }.to_h
    object = OBJECTS.keys.map{ |o| [o, generate_object(o, THEMES.index(theme))] }.to_h
    object_special = OBJECTS.keys.map{ |o| [o + 29, generate_object(o, THEMES.index(theme), true, true)] }.to_h
    object.merge!(object_special)
    border = BORDERS.to_i(16).to_s(2)[1..-1].chars.map(&:to_i).each_slice(8).to_a
    image = ChunkyPNG::Image.new(WIDTH, HEIGHT, PALETTE[2, THEMES.index(theme)])

    # PARSE MAP
    tiles = self.tiles.map(&:dup)
    objects = self.objects.reject{ |o| o[0] > 28 }.sort_by{ |o| -OBJECTS[o[0]][:pref] } # remove glitched objects
    objects.each{ |o| if o[3] > 7 then o[3] = 0 end } # remove glitched orientations

    # PAINT OBJECTS
    objects.each do |o|
      new_object = !(o[3] % 2 == 1 && [10, 11].include?(o[0])) ? object[o[0]] : object[o[0] + 29]
      if !FIXED_OBJECTS.include?(o[0]) then (1 .. o[3] / 2).each{ |i| new_object = new_object.rotate_clockwise } end
      if check_dimensions(new_object, coord(o[1]) - new_object.width / 2, coord(o[2]) - new_object.height / 2)
        image.compose!(new_object, coord(o[1]) - new_object.width / 2, coord(o[2]) - new_object.height / 2)
      end
    end

    # PAINT TILES
    tiles.each{ |row| row.unshift(1).push(1) }
    tiles.unshift([1] * (COLUMNS + 2)).push([1] * (COLUMNS + 2))
    tiles.each_with_index do |slice, row|
      slice.each_with_index do |t, column|
        if t == 0 || t == 1 # empty and full tiles
          new_tile = tile[t]
        elsif t >= 2 && t <= 17 # half tiles and curved slopes
          new_tile = tile[t - (t - 2) % 4]
          (1 .. (t - 2) % 4).each{ |i| new_tile = new_tile.rotate_clockwise }
        elsif t >= 18 && t <= 33 # small and big straight slopes
          new_tile = tile[t - (t - 2) % 4]
          if (t - 2) % 4 >= 2 then new_tile = new_tile.flip_horizontally end
          if (t - 2) % 4 == 1 || (t - 2) % 4 == 2 then new_tile = new_tile.flip_vertically end
        else
          new_tile = tile[0]
        end
        image.compose!(new_tile, DIM * column, DIM * row)
      end
    end

    # PAINT TILE BORDERS
    edge = ChunkyPNG::Image.from_file('images/b.png')
    edge = mask(edge, BLACK, PALETTE[1, THEMES.index(theme)])
    (0 .. ROWS).each do |row| # horizontal
      (0 .. 2 * (COLUMNS + 2) - 1).each do |col|
        tile_a = tiles[row][col / 2] > 33 ? 0 : tiles[row][col / 2] # these comparisons with 33 are to remove glitched tiles
        tile_b = tiles[row + 1][col / 2] > 33 ? 0 : tiles[row + 1][col / 2]
        bool = col % 2 == 0 ? (border[tile_a][3] + border[tile_b][6]) % 2 : (border[tile_a][2] + border[tile_b][7]) % 2
        if bool == 1 then image.compose!(edge.rotate_clockwise, DIM * (0.5 * col), DIM * (row + 1)) end
      end
    end
    (0 .. 2 * (ROWS + 2) - 1).each do |row| # vertical
      (0 .. COLUMNS).each do |col|
        tile_a = tiles[row / 2][col] > 33 ? 0 : tiles[row / 2][col]
        tile_b = tiles[row / 2][col + 1] > 33 ? 0 : tiles[row / 2][col + 1]
        bool = row % 2 == 0 ? (border[tile_a][0] + border[tile_b][5]) % 2 : (border[tile_a][1] + border[tile_b][4]) % 2
        if bool == 1 then image.compose!(edge, DIM * (col + 1), DIM * (0.5 * row)) end
      end
    end

    image.to_blob
  end
end
