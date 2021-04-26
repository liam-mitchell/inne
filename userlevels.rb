require_relative 'io.rb'
require_relative 'models.rb'

MIN_U_SCORES = 20 # minimum number of userlevel highscores to appear in average rankings
MIN_G_SCORES = 500 # minimum number of userlevel highscores to appear in global average rankings
PAGE_SIZE    = 20
MIN_ID       = 22715 # ID of the very first userlevel, to exclude Metanet levels

# Contains map data (tiles and objects) in a different table for performance reasons.
class UserlevelData < ActiveRecord::Base
end

# We create aliases "player" and "scores" so we don't have to specify "userlevel_"
class UserlevelScore < ActiveRecord::Base
  alias_attribute :player, :userlevel_player
  belongs_to :userlevel
  belongs_to :userlevel_player, foreign_key: :player_id

  def self.newest(id = Userlevel.min_id)
    self.where("userlevel_id >= #{id}")
  end

  def self.global
    newest(MIN_ID)
  end
end

class UserlevelPlayer < ActiveRecord::Base
  alias_attribute :scores, :userlevel_scores
  has_many :userlevel_scores, foreign_key: :player_id
  has_many :userlevel_histories, foreign_key: :player_id

  def newest(id = Userlevel.min_id)
    scores.where("userlevel_id >= #{id}")
  end  

  def range_s(rank1, rank2, ties, full = false)
    t  = ties ? 'tied_rank' : 'rank'
    ss = (full ? scores : newest).where("#{t} >= #{rank1} AND #{t} <= #{rank2}")
  end

  def range_h(rank1, rank2, ties, full = false)
    range_s(rank1, rank2, ties, full).group_by(&:rank).sort_by(&:first)
  end

  def top_ns(rank, ties, full = false)
    range_s(0, rank - 1, ties, full)
  end

  def top_n_count(rank, ties, full = false)
    top_ns(rank, ties, full).count
  end

  def points(ties, full = false)
    (full ? scores : newest).sum(ties ? '20 - tied_rank' : '20 - rank')
  end

  def avg_points(ties, full = false)
    (full ? scores : newest).average(ties ? '20 - tied_rank' : '20 - rank')
  end

  def total_score(full = false)
    (full ? scores : newest).sum(:score).to_f / 60
  end

  def avg_lead(ties, full = false)
    ss = top_ns(1, ties, full)
    count = ss.length
    avg = count == 0 ? 0 : ss.map{ |s|
      entries = s.userlevel.scores.map(&:score)
      entries[0].to_i - entries[1].to_i
    }.sum.to_f / count
    avg || 0
  end
end

class UserlevelHistory < ActiveRecord::Base  
  alias_attribute :player, :userlevel_player
  belongs_to :userlevel_player, foreign_key: :player_id

  def self.compose(rankings, rank, time)
    rankings.select{ |r| r[1] > 0 }.map do |r|
      {
        timestamp:  time,
        rank:       rank,
        player_id:  r[0].id,
        metanet_id: r[0].metanet_id,
        count:      r[1]
      }
    end
  end
end

class Userlevel < ActiveRecord::Base
  include HighScore
  alias_attribute :scores, :userlevel_scores
  has_many :userlevel_scores
  enum mode: [:solo, :coop, :race]
  # Attributes:
  #   id        - ID of the userlevel in Metanet's database (and ours)
  #   author    - Map author name
  #   author_id - Map author user ID in Metanet's database
  #   title     - Map title
  #   favs      - Number of favourites / ++s
  #   date      - Date of publishing [dd/mm/yy hh:mm] UTC times
  #   mode      - Playing mode [0 - Solo, 1 - Coop, 2 - Race]
  #   tiles     - Tile data compressed in zlib, stored in userlevel_data
  #   objects   - Object data compressed in zlib, stored in userlevel_data
  # Note: For details about how map data is stored, see the encode_ and decode_ methods below.

  # 'pref' is the drawing preference for overlaps, the lower the better
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
  "epaper", "epaper invert", "evening", "F7200", "florist", "formal", "galactic",
  "gatecrasher", "gothmode", "grapefrukt", "grappa", "gunmetal", "hazard", "heirloom",
  "holosphere", "hope", "hot", "hyperspace", "ice world", "incorporated", "infographic",
  "invert", "jaune", "juicy", "kicks", "lab", "lava world", "lemonade", "lichen",
  "lightcycle", "line", "m", "machine", "metoro", "midnight", "minus", "mir",
  "mono", "moonbase", "mustard", "mute", "nemk", "neptune", "neutrality", "noctis",
  "oceanographer", "okinami", "orbit", "pale", "papier", "papier invert", "party",
  "petal", "PICO-8", "pinku", "plus", "porphyrous", "poseidon", "powder", "pulse",
  "pumpkin", "QDUST", "quench", "regal", "replicant", "retro", "rust", "sakura",
  "shift", "shock", "simulator", "sinister", "solarized dark", "solarized light",
  "starfighter", "sunset", "supernavy", "synergy", "talisman", "toothpaste", "toxin",
  "TR-808", "tycho", "vasquez", "vectrex", "vintage", "virtual", "vivid", "void",
  "waka", "witchy", "wizard", "wyvern", "xenon", "yeti"]
  DEFAULT_PALETTE = "vasquez"
  PALETTE = ChunkyPNG::Image.from_file('images/palette.png')
  BORDERS = "100FF87E1781E0FC3F03C0FC3F03C0FC3F03C078370388FC7F87C0EC1E01C1FE3F13E"
  ROWS = 23
  COLUMNS = 42
  DIM = 44
  WIDTH = DIM * (COLUMNS + 2)
  HEIGHT = DIM * (ROWS + 2)
  INVALID_NAMES = [nil, "null", ""]

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
  def self.parse(levels, update = false)
    header = {
      date: format_date(levels[0..15].to_s),
      count: parse_int(levels[16..19]),
      page: parse_int(levels[20..23]),
      category: parse_int(levels[28..31]),
      mode: parse_int(levels[32..35])
    }
    # Note: When parsing user input (map titles and authors), we stop reading at the first null character,
    # everything after that is (should be) padding. Then, we remove non-ASCII characters.
    maps = levels[48 .. 48 + 44 * header[:count] - 1].scan(/./m).each_slice(44).to_a.map { |h|
      author = h[8..23].join.split("\x00")[0].to_s.each_byte.map{ |b| (b < 32 || b > 126) ? nil : b.chr }.compact.join.strip
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
      maps[i][:title] = map[30..157].split("\x00")[0].to_s.each_byte.map{ |b| (b < 32 || b > 126) ? nil : b.chr }.compact.join.strip
      maps[i][:tiles] = map[176..1141].scan(/./m).map{ |b| parse_int(b) }.each_slice(42).to_a
      maps[i][:objects] = map[1222..-1].scan(/./m).map{ |b| parse_int(b) }.each_slice(5).to_a
      offset += len
      i += 1
    end
    result = []
    # Update database. We pack the tile data into a binary string and compress it using zlib.
    # We do the same for object data, except we transpose it first (usually getting better compression).
    ActiveRecord::Base.transaction do
      maps.each{ |map|
        if update
          entry = Userlevel.find_or_create_by(id: map[:id])
          values = {
            title: map[:title],
            author: map[:author],
            author_id: map[:author_id],
            favs: map[:favs],
            date: map[:date],
            mode: header[:mode]
          }
          if INVALID_NAMES.include?(map[:author]) then values.delete(:author) end
          entry.update(values)
          UserlevelData.find_or_create_by(id: map[:id]).update(
            tile_data: encode_tiles(map[:tiles]),
            object_data: encode_objects(map[:objects])
          )
        else
          entry = Userlevel.find_by(id: map[:id])
        end
        result << entry
      }
    end
    result.compact
  rescue => e
    err(e)
    nil
  end

  def self.browse(qt = 10, page = 0, mode = 0, update = false)
    levels = get_levels(qt, page, mode)
    parse(levels, update)
  end

  def self.search(search = "", page = 0, mode = 0, update = false)
    levels = get_search(search, page, mode)
    parse(levels, update)
  end

  def self.sort(maps, order, invert = false)
    fields = { # possible spellings for each field, to be used for sorting or filtering
      :n => ["n", "number"],
      :id => ["id", "map id", "map_id", "level id", "level_id"],
      :title => ["title", "name"],
      :author => ["author", "player", "user", "person"],
      :date => ["date", "time", "moment", "day", "period"],
      :favs => ["fav", "favs", "++", "++s", "++'s", "favourite", "favourites"]
    }
    inverted = [:id, :date, :favs] # the order of these fields will be reversed by default
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
    if order == :date then order = :id end
    if order != :n then maps = maps.sort_by(&order) end
    if inverted.include?(order) then maps = maps.reverse end
    if invert then maps = maps.reverse end
    maps
  end

  def self.encode_tiles(tiles)
    Zlib::Deflate.deflate(tiles.flatten.map{ |t| _pack(t, 1) }.join, 9)
  end

  def self.encode_objects(objects)
    Zlib::Deflate.deflate(objects.transpose.flatten.map{ |t| _pack(t, 1) }.join, 9)
  end

  def self.decode_tiles(tile_data)
    Zlib::Inflate.inflate(tile_data).scan(/./m).map{ |b| _unpack(b) }.each_slice(42).to_a
  end

  def self.decode_objects(object_data)
    dec = Zlib::Inflate.inflate(object_data)
    dec.scan(/./m).map{ |b| _unpack(b) }.each_slice((dec.size / 5).round).to_a.transpose
  end

  def self.min_id
    Userlevel.where(scored: true).order(id: :desc).limit(USERLEVEL_REPORT_SIZE).last.id
  end

  def self.newest(id = min_id)
    self.where("id >= #{id}")
  end

  def self.global
    newest(MIN_ID)
  end

  def self.spreads(n, small = false, player_id = nil, full = false)
    scores = full ? UserlevelScore.global : UserlevelScore.newest
    bench(:start) if BENCHMARK
    # retrieve player's 0ths if necessary
    ids = scores.where(rank: 0, player_id: player_id).pluck(:userlevel_id) if !player_id.nil?
    # retrieve required scores and compute spreads
    ret1 = scores.where(rank: 0)
    ret1 = ret1.where(userlevel_id: ids) if !player_id.nil?
    ret1 = ret1.pluck(:userlevel_id, :score).to_h
    ret2 = scores.where(rank: n)
    ret2 = ret2.where(userlevel_id: ids) if !player_id.nil?
    ret2 = ret2.pluck(:userlevel_id, :score).to_h
    ret = ret2.map{ |id, s| [id, ret1[id] - s] }
              .sort_by{ |id, s| small ? s : -s }
              .take(NUM_ENTRIES)
              .to_h
    # retrieve player names
    pnames = scores.where(userlevel_id: ret.keys, rank: 0)
                   .joins("INNER JOIN userlevel_players ON userlevel_players.id = userlevel_scores.player_id")
                   .pluck('userlevel_scores.userlevel_id', 'userlevel_players.name')
                   .to_h
    ret = ret.map{ |id, s| [id.to_s, s / 60.0, pnames[id]] }
    bench(:step) if BENCHMARK
    ret
  end

  # @par player_id: Excludes levels in which the player is tied for 0th
  # @par maxed:     Whether we are computing maxed or maxable levels
  # @par full:      Whether we use all userlevels or only the newest ones
  # @par count:     Whether to query all info or only return the map count
  def self.ties(player_id = nil, maxed = false, full = false, count = false)
    scores = full ? UserlevelScore.global : UserlevelScore.newest
    bench(:start) if BENCHMARK
    # retrieve most tied for 0th leves
    ret = scores.where(tied_rank: 0)
                .group(:userlevel_id)
                .order(!maxed ? 'count(id) desc' : '', :userlevel_id)
                .having('count(id) >= 3')
                .having(!player_id.nil? ? 'amount = 0' : '')
                .pluck('userlevel_id', 'count(id)', !player_id.nil? ? "count(if(player_id = #{player_id}, player_id, NULL)) AS amount" : '1')
                .map{ |s| s[0..1] }
                .to_h
    # retrieve total score counts for each level (to compare against the tie count and determine maxes)
    counts = scores.where(userlevel_id: ret.keys)
                   .group(:userlevel_id)
                   .order('count(id) desc')
                   .count(:id)
    if !count
      # retrieve player names owning the 0ths on said level
      pnames = scores.where(userlevel_id: ret.keys, rank: 0)
                     .joins("INNER JOIN userlevel_players ON userlevel_players.id = userlevel_scores.player_id")
                     .pluck('userlevel_scores.userlevel_id', 'userlevel_players.name')
                     .to_h
      # retrieve userlevels
      userl = Userlevel.where(id: ret.keys)
                       .map{ |u| [u.id, u] }
                       .to_h
      ret = ret.map{ |id, c| [userl[id], c, counts[id], pnames[id]] }
    else
      ret = maxed ? ret.count{ |id, c| counts[id] == c } : ret.count
    end
    bench(:step) if BENCHMARK
    ret
  end

  # Because of the way the query is done I use a ranking type instead of yield blocks
  def self.rank(type, ties = false, par = nil, full = false, global = false)
    scores = global ? UserlevelScore.global : UserlevelScore.newest

    bench(:start) if BENCHMARK
    case type
    when :rank
      scores = scores.where("#{ties ? "tied_rank" : "rank"} <= #{par}")
                     .group(:player_id)
                     .order('count_id desc')
                     .count(:id)
    when :tied
      scores_w  = scores.where("tied_rank <= #{par}")
                        .group(:player_id)
                        .order('count_id desc')
                        .count(:id)
      scores_wo = scores.where("rank <= #{par}")
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
                     .having("count(player_id) >= #{global ? MIN_G_SCORES : MIN_U_SCORES}")
                     .order("avg(#{ties ? "20 - tied_rank" : "20 - rank"}) desc")
                     .average(ties ? "20 - tied_rank" : "20 - rank")
    when :avg_rank
      scores = scores.select("count(player_id)")
                     .group(:player_id)
                     .having("count(player_id) >= #{global ? MIN_G_SCORES : MIN_U_SCORES}")
                     .order("avg(#{ties ? "tied_rank" : "rank"})")
                     .average(ties ? "tied_rank" : "rank")
    when :avg_lead 
      scores = scores.where(rank: [0, 1])
                     .pluck(:player_id, :userlevel_id, :score)
                     .group_by{ |s| s[1] }
                     .reject{ |u, s| s.count < 2 }
                     .map{ |u, s| [s[0][0], s[0][2] - s[1][2]] }
                     .group_by{ |s| s[0] }
                     .map{ |p, s| [p, s.map(&:last).sum / (60.0 * s.map(&:last).count)] }
                     .sort_by{ |p, s| -s }
    when :score
      scores = scores.group(:player_id)
                     .order("sum(score) desc")
                     .sum('score / 60')
    end
    bench(:step) if BENCHMARK

    scores = scores.take(NUM_ENTRIES) if !full
    # find all players in advance (better performance)
    players = UserlevelPlayer.where(id: scores.map(&:first))
                    .map{ |p| [p.id, p] }
                    .to_h
    scores.map{ |p, c| [players[p], c] }
          .reject{ |p, c| c <= 0  }
  end

  # technical
  def self.sanitize(string, par)
    sanitize_sql_for_conditions([string, par])
  end

  def tiles
    Userlevel.decode_tiles(UserlevelData.find(self.id).tile_data)
  end

  def objects
    Userlevel.decode_objects(UserlevelData.find(self.id).object_data)
  end

  def format_scores
    update_scores if !OFFLINE_STRICT
    if scores.count == 0
      board = "This userlevel has no highscores!"
    else
      board = scores.map{ |s| { score: s.score / 60.0, player: s.player.name } }
      pad = board.map{ |s| s[:score] }.max.to_i.to_s.length + 4
      board.each_with_index.map{ |s, i|
        "#{HighScore.format_rank(i)}: #{format_string(s[:player])} - #{"%#{pad}.3f" % [s[:score]]}"
      }.join("\n")
    end
  end

  # Generate a file with the usual userlevel format
  def convert
    # HEADER
    data = ("\x00" * 4).force_encoding("ascii-8bit")   # magic number ?
    data << _pack(1230 + 5 * self.objects.size, 4)     # filesize
    data << ("\xFF" * 4).force_encoding("ascii-8bit")  # static data
    data << _pack(Userlevel.modes[self.mode], 4)       # game mode
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

  def screenshot(theme = DEFAULT_PALETTE)
    themes = THEMES.map(&:downcase)
    theme = theme.downcase
    if !themes.include?(theme) then theme = DEFAULT_PALETTE end

    # INITIALIZE IMAGES
    tile = [0, 1, 2, 6, 10, 14, 18, 22, 26, 30].map{ |o| [o, generate_object(o, themes.index(theme), false)] }.to_h
    object = OBJECTS.keys.map{ |o| [o, generate_object(o, themes.index(theme))] }.to_h
    object_special = OBJECTS.keys.map{ |o| [o + 29, generate_object(o, themes.index(theme), true, true)] }.to_h
    object.merge!(object_special)
    border = BORDERS.to_i(16).to_s(2)[1..-1].chars.map(&:to_i).each_slice(8).to_a
    image = ChunkyPNG::Image.new(WIDTH, HEIGHT, PALETTE[2, themes.index(theme)])

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
    tiles = tiles.map{ |row| row.map{ |tile| tile > 33 ? 0 : tile } } # remove glitched tiles
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
    edge = mask(edge, BLACK, PALETTE[1, themes.index(theme)])
    (0 .. ROWS).each do |row| # horizontal
      (0 .. 2 * (COLUMNS + 2) - 1).each do |col|
        tile_a = tiles[row][col / 2]
        tile_b = tiles[row + 1][col / 2]
        bool = col % 2 == 0 ? (border[tile_a][3] + border[tile_b][6]) % 2 : (border[tile_a][2] + border[tile_b][7]) % 2
        if bool == 1 then image.compose!(edge.rotate_clockwise, DIM * (0.5 * col), DIM * (row + 1)) end
      end
    end
    (0 .. 2 * (ROWS + 2) - 1).each do |row| # vertical
      (0 .. COLUMNS).each do |col|
        tile_a = tiles[row / 2][col]
        tile_b = tiles[row / 2][col + 1]
        bool = row % 2 == 0 ? (border[tile_a][0] + border[tile_b][5]) % 2 : (border[tile_a][1] + border[tile_b][4]) % 2
        if bool == 1 then image.compose!(edge, DIM * (col + 1), DIM * (0.5 * row)) end
      end
    end

    image.to_blob
  end
end

# <---------------------------------------------------------------------------->
# <---                           MESSAGES                                   --->
# <---------------------------------------------------------------------------->

def format_userlevels(maps, page, range)
  # Calculate required column padding
  max_padding = {n: 3, id: 6, title: 30, author: 16, date: 14, favs: 4 }
  min_padding = {n: 2, id: 2, title:  5, author:  6, date: 14, favs: 2 }
  def_padding = {n: 3, id: 6, title: 25, author: 16, date: 14, favs: 2 }
  if !maps.nil? && !maps.empty?
    n_padding =      [ [ range.to_a.max.to_s.length,                        max_padding[:n]     ].min, min_padding[:n]      ].max
    id_padding =     [ [ maps.map{ |map| map[:id].to_i }.max.to_s.length,   max_padding[:id]    ].min, min_padding[:id]     ].max
    title_padding  = [ [ maps.map{ |map| map[:title].to_s.length }.max,     max_padding[:title] ].min, min_padding[:title]  ].max
    author_padding = [ [ maps.map{ |map| map[:author].to_s.length }.max,    max_padding[:title] ].min, min_padding[:author] ].max
    date_padding   = [ [ maps.map{ |map| map[:date].to_s.length }.max,      max_padding[:date]  ].min, min_padding[:date]   ].max
    favs_padding   = [ [ maps.map{ |map| map[:favs].to_i }.max.to_s.length, max_padding[:favs]  ].min, min_padding[:favs]   ].max
    padding = {n: n_padding, id: id_padding, title: title_padding, author: author_padding, date: date_padding, favs: favs_padding }
  else
    padding = def_padding
  end

  # Print header
  output = "```\n"
  output += "%-#{padding[:n]}.#{padding[:n]}s " % "N"
  output += "%-#{padding[:id]}.#{padding[:id]}s " % "ID"
  output += "%-#{padding[:title]}.#{padding[:title]}s " % "Title"
  output += "%-#{padding[:author]}.#{padding[:author]}s " % "Author"
  output += "%-#{padding[:date]}.#{padding[:date]}s " % "Date"
  output += "%-#{padding[:favs]}.#{padding[:favs]}s" % "++"
  output += "\n"
  output += "-" * (padding.inject(0){ |sum, pad| sum += pad[1] } + padding.size - 1) + "\n"

  # Print levels
  if maps.nil? || maps.empty?
    output += " " * (padding.inject(0){ |sum, pad| sum += pad[1] } + padding.size - 1) + "\n"
  else
    maps.each_with_index{ |m, i|
      line = "%#{padding[:n]}.#{padding[:n]}s " % (PAGE_SIZE * page + i).to_s
      padding.reject{ |k, v| k == :n  }.each{ |k, v|
        if m[k].is_a?(Integer)
          line += "%#{padding[k]}.#{padding[k]}s " % m[k].to_s
        else
          line += "%-#{padding[k]}.#{padding[k]}s " % m[k].to_s
        end
      }
      output << line + "\n"
    }
  end
  output + "```"
end

def send_userlevel_browse(event)
  msg = event.content
  user = event.user.name
  page = msg[/page\s*([0-9][0-9]?)/i, 1].to_i || 0
  part = msg[/part\s*([0-9][0-9]?)/i, 1].to_i || 0
  order = msg[/(order|sort)\s*(by)?\s*((\w|\+|-)*)/i, 3] || ""
  invert = order.strip[/\A-*/i].length % 2 == 1 || false
  order.delete!("-")
  category = 10
  categories = {
     0 => ["All",        "all"],
     1 => ["Oldest",     "oldest"],
     7 => ["Best",       "best"],
     8 => ["Featured",   "featured"],
     9 => ["Top Weekly", "top"],
    10 => ["Newest",     "newest"],
    11 => ["Hardest",    "hardest"]
  }

  categories.each{ |id, cat| category = id if !!(msg =~ /#{cat[1]}/i) }
  if category.nil?
    event << "Error browsing userlevels: You need to specify a tab to browse (best, featured, top, newest, hardest, all)."
    return
  end

  maps = [0, 1, 10].include?(category) ? Userlevel.all : Userlevel::browse(category, part, 0, false)
  if maps.nil?
    event << "Error downloading maps (server down?) or parsing maps (unknown format received?)."
    return
  end

  if order.empty? && category == 10 then invert = !invert end
  maps = Userlevel::sort(maps, order, invert)
  count = maps.size
  pages = (maps.size.to_f / PAGE_SIZE).ceil
  page = pages - 1 if page > pages - 1 unless pages == 0
  range = (PAGE_SIZE * page .. PAGE_SIZE * (page + 1) - 1)
  maps = maps[range]

  output = "Browsing **" + categories[category][0].to_s.upcase + "**. "
  output += "Page **" + page.to_s + "/" + (pages - 1).to_s + "**. "
  output += "Order: **" + (order == "" ? "DEFAULT" : order.to_s.upcase) + "**. Filter: **DEFAULT**.\n"
  output += "Date: " + Time.now.to_s + ".\n"
  output += "Total results: **" + count.to_s + "**. Use \"page <number>\" to navigate the pages.\n"
  output += format_userlevels(Userlevel::serial(maps), page, range)

  event << output
rescue => e
  err(e)
  event << "Error downloading maps (server is not responding)."
end

def send_userlevel_search(event)
  msg = event.content
  user = event.user.name
  search = msg[/search\s*(for)?\s*#{parse_term}/i, 3] || ""
  page = msg[/page\s*([0-9][0-9]?)/i, 1].to_i || 0
  part = msg[/part\s*([0-9][0-9]?)/i, 1].to_i || 0
  author = parse_userlevel_author(msg)
  order = msg[/(order|sort)\s*(by)?\s*((\w|\+|-)*)/i, 3] || ""
  invert = order.strip[/\A-*/i].length % 2 == 1
  order.delete!("-")

  if !search.ascii_only?
    event << "Sorry! We can only perform ASCII-only searches."
  else
    search = search[0..63] # truncate search query to fit under the character limit
    maps = author.empty? ? Userlevel::search(search, part, 0, false) : Userlevel.where(author: author)
    if maps.nil?
      event << "Error downloading maps (server down?) or parsing maps (unknown format received?)."
      return
    end
    maps = Userlevel::sort(maps, order, invert)
    count = maps.size
    pages = (maps.size.to_f / PAGE_SIZE).ceil
    page = pages - 1 if page > pages - 1 unless pages == 0
    range = (PAGE_SIZE * page .. PAGE_SIZE * (page + 1) - 1)
    maps = maps[range]

    output = "Searching for \"" + (!search.empty? ? ("**" + search + "**") : "") + "\". "
    output += "Page **" + page.to_s + "/" + (pages > 0 ? (pages - 1).to_s : "0") + "**. "
    output += "Order: **" + (order == "" ? "DEFAULT" : order.to_s.upcase) + "**. Filter: **DEFAULT**.\n"
    output += "Date: " + Time.now.to_s + ".\n"
    output += "Total results: **" + count.to_s + "**. Use \"page <number>\" to navigate the pages.\n"
    output += format_userlevels(Userlevel::serial(maps), page, range)
  end

  event << output
rescue => e
  err(e)
  event << "Error downloading maps (server is not responding)."
end

# TODO: When downloading by name is implemented, the way to get the ID in the
#       following methods must be adapted as well because it's too greedy now.
def send_userlevel_download(event)
  msg = event.content
  # id = msg[/download\s*(\d+)/i, 1] || -1
  id = msg[/\d+/i] || -1

  if id == -1
    event << "You need to specify the numerical ID of the map to download (e.g. `download userlevel 72807`)."
  else
    map = Userlevel::where(id: id)
    if map.nil? || map.empty?
      event << "The map with the specified ID is not present in the database."
    else
      map = map[0]
      file = map.convert
      output = "Downloading userlevel `" + map.title + "` with ID `" + map.id.to_s
      output += "` by `" + (map.author.to_s.empty? ? " " : map.author.to_s) + "` on " + Time.now.to_s + ".\n"
      event << output
      send_file(event, file, map.id.to_s, true)
    end
  end
end

def send_userlevel_screenshot(event, userlevel = nil)
  msg = event.content
  id = userlevel.nil? ? (msg[/\d+/i] || -1) : userlevel.id
  palette = userlevel.nil? ? msg[/#{parse_term}/i, 2] || Userlevel::DEFAULT_PALETTE : Userlevel::DEFAULT_PALETTE

  if id == -1
    event << "You need to specify the name or the numerical ID of the map (e.g. `screenshot of userlevel 78414`).\n"
    event << "If you don't know it, you can **search** it (e.g. `userlevel search for \"the end\"`)."
  else
    map = Userlevel::where(id: id)
    if map.nil? || map.empty?
      event << "The map with the specified ID is not present in the database."
    else
      index = Userlevel::THEMES.map(&:downcase).index(palette.downcase)
      if index.nil?
        event << "The palette `" + palette + "` doesn't exit. Using default: `" + Userlevel::DEFAULT_PALETTE + "`."
        palette = Userlevel::DEFAULT_PALETTE
        index = Userlevel::THEMES.index(Userlevel::DEFAULT_PALETTE)
      else 
        palette = Userlevel::THEMES[index]
      end
      map = map[0]
      file = map.screenshot(Userlevel::THEMES[index])
      output = "Screenshot of userlevel `" + map.title + "` with ID `" + map.id.to_s
      output += "` by `" + (map.author.to_s.empty? ? " " : map.author.to_s) + "` using palette `"
      output += palette + "` on " + Time.now.to_s + ".\n"
      event << output
      send_file(event, file, map.id.to_s + ".png", true)
    end
  end
end

def send_userlevel_scores(event)
  msg = event.content
  # id = msg[/scores\s*(for|of)?\s*(\d+)/i, 2] || -1
  id = msg[/\d+/i] || -1

  if id == -1
    event << "You need to specify the name or the numerical ID of the map (e.g. `userlevel scores for 78414`).\n"
    event << "If you don't know it, you can **search** it (e.g. `userlevel search for \"the end\"`)."
  else
    map = Userlevel.find(id)
    if map.nil?
      event << "The map with the specified ID is not present in the database."
    else
      output = "Scores of userlevel `" + map.title + "` with ID `" + map.id.to_s
      output += "` by `" + (map.author.to_s.empty? ? " " : map.author.to_s) + "` on " + Time.now.to_s + ".\n"
      event << output + "```" + map.format_scores + "```"
    end
  end
end

def send_userlevel_rankings(event)
  msg = event.content
  rank = parse_rank(msg) || 1
  rank = 1 if rank < 0
  rank = 20 if rank > 20
  ties = !!msg[/with ties/i]
  full = parse_global(msg)
  type = ""

  if msg =~ /average/i
    if msg =~ /point/i
      top = Userlevel.rank(:avg_points, ties, nil, false, full)
      type = "average points"
    elsif msg =~ /lead/i
      top = Userlevel.rank(:avg_lead, nil, nil, false, full)
      type = "average lead"
    else
      top = Userlevel.rank(:avg_rank, ties, nil, false, full)
      type = "average rank"
    end
  elsif msg =~ /point/i
    top = Userlevel.rank(:points, ties, nil, false, full)
    type = "total points"
  elsif msg =~ /score/i
    top = Userlevel.rank(:score, nil, nil, false, full)
    type = "total score"
  elsif msg =~ /tied/i
    top = Userlevel.rank(:tied, ties, rank - 1, false, full)
    type = "tied #{format_rank(rank)}"
  else
    top = Userlevel.rank(:rank, ties, rank - 1, false, full)
    type = format_rank(rank)
  end

  score_padding = top.map{ |r| r[1].to_i.to_s.length }.max
  name_padding = top.map{ |r| r[0].name.length }.max
  format = top[0][1].is_a?(Integer) ? "%#{score_padding}d" : "%#{score_padding + 4}.3f"
  full = format_global(full)
  top = "```" + top.each_with_index
           .map{ |p, i| "#{"%02d" % i}: #{format_string(p[0].name, name_padding)} - #{format % p[1]}" }
           .join("\n") + "```"
  top.concat("Minimum number of scores required: #{full ? MIN_G_SCORES : MIN_U_SCORES}") if msg =~ /average/i

  header = "Userlevel #{full}#{type} #{ties ? "with ties " : ""}rankings #{format_time}:"
  length = header.length + top.length
  event << header
  length < DISCORD_LIMIT ? event << top : send_file(event, top[3..-4], "userlevel-rankings.txt", false)
end

def send_userlevel_count(event)
  msg = event.content
  player = parse_player(msg, event.user.name, true)
  rank = !!(msg =~ /0th/i) ? 1 : (parse_rank(msg) || 1)
  ties = !!(msg =~ /ties/i)
  tied = !!(msg =~ /\btied\b/i)
  full = parse_global(msg)
  if tied
    count = player.top_n_count(rank, true, full) - player.top_n_count(rank, false, full)
  else
    count = player.top_n_count(rank, ties, full)
  end
  header = format_rank(rank)
  ties = format_ties(ties)
  tied = format_tied(tied)
  full = format_global(full)
  event << "#{player.name} has #{count} #{full}#{tied}userlevel #{header} scores#{ties}."
end

def send_userlevel_points(event)
  msg    = event.content
  player = parse_player(msg, event.user.name, true)
  ties   = !!(msg =~ /ties/i)
  full   = parse_global(msg)
  points = player.points(ties, full)
  ties   = format_ties(ties)
  full   = format_global(full)
  event << "#{player.name} has #{points} #{full}userlevel points#{ties}."
end

def send_userlevel_avg_points(event)
  msg    = event.content
  player = parse_player(msg, event.user.name, true)
  ties   = !!(msg =~ /ties/i)
  full   = parse_global(msg)
  avg    = player.avg_points(ties, full)
  ties   = format_ties(ties)
  full = format_global(full)
  event << "#{player.name} has #{"%.3f" % avg} average #{full}userlevel points#{ties}."
end

def send_userlevel_avg_rank(event)
  msg    = event.content
  player = parse_player(msg, event.user.name, true)
  ties   = !!(msg =~ /ties/i)
  full   = parse_global(msg)
  avg    = 20 - player.avg_points(ties, full)
  ties   = format_ties(ties)
  full   = format_global(full)
  event << "#{player.name} has an average #{"%.3f" % avg} #{full}userlevel rank#{ties}."
end

def send_userlevel_total_score(event)
  msg    = event.content
  player = parse_player(msg, event.user.name, true)
  full   = parse_global(msg)
  score  = player.total_score(full)
  full   = format_global(full)
  event << "#{player.name} has #{"%.3f" % score}s of total #{full}userlevel score."
end

def send_userlevel_avg_lead(event)
  msg    = event.content
  player = parse_player(msg, event.user.name, true)
  ties   = !!(msg =~ /ties/i)
  full   = parse_global(msg)
  avg    = player.avg_lead(ties, full)
  ties   = format_ties(ties)
  full   = format_global(full)
  event << "#{player.name} has an average #{"%.3f" % avg} #{full}userlevel 0th lead#{ties}."
end

def send_userlevel_list(event)
  msg    = event.content
  player = parse_player(msg, event.user.name, true)
  rank   = parse_rank(msg) || 20
  bott   = parse_bottom_rank(msg) || 0
  ties   = !!(msg =~ /ties/i)
  full   = parse_global(msg)
  if rank == 20 && bott == 0 && !!msg[/0th/i]
    rank = 1
    bott = 0
  end
  all = player.range_h(bott, rank - 1, ties, full)

  res = all.map{ |rank, scores|
    rank.to_s.rjust(2, '0') + ":\n" + scores.map{ |s|
      "  #{HighScore.format_rank(s.rank)}: [#{s.userlevel.id.to_s.rjust(6)}] #{s.userlevel.title} (#{"%.3f" % [s.score / 60]})"
    }.join("\n")
  }.join("\n")
  send_file(event, res, "#{full ? "global-" : ""}userlevel-scores-#{player.name}.txt")
end

def send_userlevel_stats(event)
  msg    = event.content
  player = parse_player(msg, event.user.name, true)
  ties   = !!(msg =~ /ties/i)
  full   = parse_global(msg)
  counts = player.range_h(0, 19, ties, full).map{ |rank, scores| [rank, scores.length] }

  histogram = AsciiCharts::Cartesian.new(
    counts,
    bar: true,
    hide_zero: true,
    max_y_vals: 15,
    title: 'Histogram'
  ).draw

  totals  = counts.map{ |rank, count| "#{HighScore.format_rank(rank)}: #{"   %5d" % count}" }.join("\n\t")
  overall = "Totals:    %5d" % counts.reduce(0){ |sum, c| sum += c[1] }

  full = format_global(full)
  event << "#{full.capitalize}userlevels highscoring stats for #{player.name} #{format_time}:"
  event << "```          Scores\n\t#{totals}\n#{overall}\n#{histogram}```"
end

def send_userlevel_spreads(event)
  msg    = event.content
  n      = (msg[/([0-9][0-9]?)(st|nd|rd|th)/, 1] || 1).to_i
  player = parse_player(msg, nil, true, true, false)
  small  = !!(msg =~ /smallest/)
  full   = parse_global(msg)
  raise "I can't show you the spread between 0th and 0th..." if n == 0

  spreads  = Userlevel.spreads(n, small, player.nil? ? nil : player.id, full)
  namepad  = spreads.map{ |s| s[0].length }.max
  scorepad = spreads.map{ |s| s[1] }.max.to_i.to_s.length + 4
  spreads  = spreads.each_with_index
                    .map { |s, i| "#{"%02d" % i}: #{"%-#{namepad}s" % s[0]} - #{"%#{scorepad}.3f" % s[1]} - #{s[2]}"}
                    .join("\n")

  spread = small ? "smallest" : "largest"
  rank   = (n == 1 ? "1st" : (n == 2 ? "2nd" : (n == 3 ? "3rd" : "#{n}th")))
  full   = format_global(full)
  event << "#{full.capitalize}userlevels #{!player.nil? ? "owned by #{player.name} " : ""}with the #{spread} spread between 0th and #{rank}:\n```#{spreads}```"
end

def send_userlevel_maxed(event)
  msg    = event.content
  player = parse_player(msg, nil, true, true, false)
  full   = parse_global(msg)
  ties   = Userlevel.ties(player.nil? ? nil : player.id, true, full)
                    .select { |s| s[1] == s[2] }
                    .map { |s| "#{"%6d" % s[0].id} - #{"%6d" % s[0].author_id} - #{format_string(s[3])}" }
  count  = ties.count{ |s| s.length > 1 }
  player = player.nil? ? "" : " without " + player.name
  full   = format_global(full)
  block  = "    ID - Author - Player\n#{ties.join("\n")}"
  event << "Potentially maxed #{full}userlevels (with all scores tied for 0th) #{format_time}#{player}:"
  count <= 20 ? event << "```#{block}```" : send_file(event, block, "maxed-userlevels.txt", false)
  event << "There's a total of #{count} potentially maxed userlevels."
end

def send_userlevel_maxable(event)
  msg    = event.content
  player = parse_player(msg, nil, true, true, false)
  full   = parse_global(msg)
  ties   = Userlevel.ties(player.nil? ? nil : player.id, false, full)
            .select { |s| s[1] < s[2] }
            .sort_by { |s| -s[1] }
            .take(NUM_ENTRIES)
            .map { |s| "#{"%6s" % s[0].id} - #{"%4d" % s[1]} - #{"%6d" % s[0].author_id} - #{format_string(s[3])}" }
            .join("\n")
  player = player.nil? ? "" : " without " + player.name
  full   = format_global(full)
  event << "#{full.capitalize}userlevels with the most ties for 0th #{format_time}#{player}:"
  event << "```    ID - Ties - Author - Player\n#{ties}```"
end

def send_random_userlevel(event)
  msg    = event.content
  author = parse_userlevel_author(msg) || ""
  amount = [msg.remove(author)[/\d+/].to_i || 1, PAGE_SIZE].min
  mode   = msg =~ /\bcoop\b/i ? :coop : (msg =~ /\brace\b/i ? :race : :solo)
  full   = !parse_newest(msg)
  levels = full ? Userlevel.global : Userlevel.newest

  if amount > 1
    maps = levels.where(mode: mode, author: author).sample(amount)
    event << "Random selection of #{amount} #{mode.to_s} #{format_global(full)}userlevels#{!author.empty? ? " by #{author}" : ""}:" + format_userlevels(Userlevel::serial(maps), 0, (0..amount - 1))
  else
    map = levels.where(mode: mode, author: author).sample
    send_userlevel_screenshot(event, map)
  end
end

def send_userlevel_mapping_summary(event)
  msg    = event.content
  player = msg[/(for|of)\s*(.*)/i, 2]
  full   = parse_global(msg)

  userlevels = Userlevel.global.where(mode: :solo)
  maps = player.nil? ? userlevels : userlevels.where(author: player)
  count = maps.count
  event << "Userlevel mapping summary#{" for #{player}" if !player.nil?}:```"
  event << "Maps:           #{count}"
  if player.nil?
    authors  = userlevels.distinct.count(:author_id)
    prolific = userlevels.where.not(author: nil).group(:author_id).order("count(id) desc").count(:id).first
    popular  = userlevels.where.not(author: nil).group(:author_id).order("sum(favs) desc").sum(:favs).first
    refined  = userlevels.where.not(author: nil).group(:author_id).order("avg(favs) desc").average(:favs).first
    event << "Authors:        #{authors}"
    event << "Maps / author:  #{"%.3f" % (count.to_f / authors)}"
    event << "Most maps:      #{prolific.last} (#{Userlevel.find_by(author_id: prolific.first).author})"
    event << "Most ++'s:      #{popular.last} (#{Userlevel.find_by(author_id: popular.first).author})"
    event << "Most avg ++'s:  #{"%.3f" % refined.last} (#{Userlevel.find_by(author_id: refined.first).author})"
  end
  if !maps.empty?
    first = maps.order(:id).first
    event << "First map:      #{first.date} (#{first.id})"
    last = maps.order(id: :desc).first
    event << "Last map:       #{last.date} (#{last.id})"
    best = maps.order(favs: :desc).first
    event << "Most ++'ed map: #{best.favs} (#{best.id})"
    sum = maps.sum(:favs).to_i
    event << "Total ++'s:     #{sum}"
    avg = sum.to_f / count
    event << "Avg. ++'s:      #{"%.3f" % avg}"
  end
  event << "```"
end

def send_userlevel_highscoring_summary(event)
  msg    = event.content
  player = msg[/(for|of)\s*(.*)/i, 2]
  full   = parse_global(msg)
  if full && player.nil?
    event.send_message("The global userlevel highscoring summary on command is disabled for now until it's optimized, you can still do the regular summary, or the global summary for a specific player.")
    return
  end

  userlevels = full ? Userlevel.global.where(mode: :solo) : Userlevel.newest.where(mode: :solo)
  maps = player.nil? ? userlevels : userlevels.where(author: player)
  count = maps.count

  userlevel_scores = full ? UserlevelScore.global : UserlevelScore.newest
  sanitized_name = Userlevel.sanitize("userlevel_players.name = ?", player)
  scores = player.nil? ? userlevel_scores : userlevel_scores.joins("INNER JOIN userlevel_players ON userlevel_players.id = userlevel_scores.player_id").where(sanitized_name)
  count_a = userlevel_scores.distinct.count(:userlevel_id)
  count_s = scores.count
  event << "#{format_global(full).capitalize}userlevel highscoring summary#{" for #{player}" if !player.nil?}:```"
  if player.nil?
    min = full ? MIN_G_SCORES : MIN_U_SCORES
    scorers   = scores.distinct.count(:player_id)
    prolific1 = scores.group(:player_id).order("count(id) desc").count(:id).first
    prolific2 = scores.where("rank <= 9").group(:player_id).order("count(id) desc").count(:id).first
    prolific3 = scores.where("rank <= 4").group(:player_id).order("count(id) desc").count(:id).first
    prolific4 = scores.where("rank = 0").group(:player_id).order("count(id) desc").count(:id).first
    highscore = scores.group(:player_id).order("sum(score) desc").sum(:score).first
    manypoint = scores.group(:player_id).order("sum(20 - rank) desc").sum("20 - rank").first
    averarank = scores.select("count(rank)").group(:player_id).having("count(rank) >= #{min}").order("avg(rank)").average(:rank).first
    maxes     = Userlevel.ties(nil, true,  full, true)
    maxables  = Userlevel.ties(nil, false, full, true)
    tls   = scores.where(rank: 0).sum(:score).to_f / 60.0
    tls_p = highscore.last.to_f / 60.0
    event << "Scored maps:      #{count_a}"
    event << "Unscored maps:    #{count - count_a}"
    event << "Scores:           #{count_s}"
    event << "Players:          #{scorers}"
    event << "Scores / map:     #{"%.3f" % (count_s.to_f / count)}"
    event << "Scores / player:  #{"%.3f" % (count_s.to_f / scorers)}"
    event << "Total score:      #{"%.3f" % tls}"
    event << "Avg. score:       #{"%.3f" % (tls / count_a)}"
    event << "Maxable maps:     #{maxables}"
    event << "Maxed maps:       #{maxes}"
    event << "Most Top20s:      #{prolific1.last} (#{UserlevelPlayer.find(prolific1.first).name})"
    event << "Most Top10s:      #{prolific2.last} (#{UserlevelPlayer.find(prolific2.first).name})"
    event << "Most Top5s:       #{prolific3.last} (#{UserlevelPlayer.find(prolific3.first).name})"
    event << "Most 0ths:        #{prolific4.last} (#{UserlevelPlayer.find(prolific4.first).name})"
    event << "Most total score: #{"%.3f" % tls_p} (#{UserlevelPlayer.find(highscore.first).name})"
    event << "Most points:      #{manypoint.last} (#{UserlevelPlayer.find(manypoint.first).name})"
    event << "Best avg rank:    #{averarank.last} (#{UserlevelPlayer.find(averarank.first).name})" rescue nil
  else
    tls = scores.sum(:score).to_f / 60.0
    event << "Total Top20s: #{count_s}"
    event << "Total Top10s: #{scores.where("rank <= 9").count}"
    event << "Total Top5s:  #{scores.where("rank <= 4").count}"
    event << "Total 0ths:   #{scores.where("rank = 0").count}"
    event << "Total score:  #{"%.3f" % tls}"
    event << "Avg. score:   #{"%.3f" % (tls / count_s)}"
    event << "Total points: #{scores.sum("20 - rank")}"
    event << "Avg. rank:    #{"%.3f" % scores.average(:rank)}"
  end
  event << "```"
end

def send_userlevel_summary(event)
  msg = event.content
  mapping     = !!msg[/mapping/i]
  highscoring = !!msg[/highscoring/i]
  both        = !(mapping || highscoring)
  send_userlevel_mapping_summary(event)     if mapping     || both
  send_userlevel_highscoring_summary(event) if highscoring || both
end

# Exports userlevel database (bar level data) to CSV, for testing purposes.
def csv(event)
  s = "id,author_id,author,title,favs,date,mode\n"
  Userlevel.all.each{ |m|
    s << m[:id].to_s + "," + m[:author_id].to_s + "," + m[:author].to_s.tr(',\'"','') + "," + m[:title].to_s.tr(',\'"','') + "," + m[:favs].to_s + "," + m[:date].to_s + "," + m[:mode].to_s + "\n"
  }
  File.write("userlevels.csv", s)
  event << "CSV exported."
end

def respond_userlevels(event)
  msg = event.content
  msg.sub!(/\A<@!?[0-9]*> */, '') # strip off the @inne++ mention, if present

  # methods not requiring to browse the database
  if !(msg =~ /"/i)
    # global methods
    if  !msg[NAME_PATTERN, 2]
      send_userlevel_rankings(event)    if msg =~ /\brank/i
    end
    send_userlevel_count(event)       if msg =~ /how many/i
    send_userlevel_points(event)      if msg =~ /point/i && msg !~ /rank/i && msg !~ /average/i
    send_userlevel_total_score(event) if msg =~ /total score/i && msg !~ /rank/i
    send_userlevel_avg_points(event)  if msg =~ /average/i && msg =~ /point/i && msg !~ /rank/i
    send_userlevel_avg_rank(event)    if msg =~ /average/i && msg =~ /rank/i && !!msg[NAME_PATTERN, 2]
    send_userlevel_avg_lead(event)    if msg =~ /average/i && msg =~ /lead/i && msg !~ /rank/i
    send_userlevel_list(event)        if msg =~ /\blist\b/i
    send_userlevel_stats(event)       if msg =~ /stat/i
    send_userlevel_spreads(event)     if msg =~ /spread/i
    send_userlevel_maxed(event)       if msg =~ /maxed/i
    send_userlevel_maxable(event)     if msg =~ /maxable/i
    send_userlevel_summary(event)     if msg =~ /summary/i
  end

  send_userlevel_browse(event)     if msg =~ /\bbrowse\b/i || msg =~ /\bshow\b/i
  send_userlevel_search(event)     if msg =~ /\bsearch\b/i
  send_userlevel_download(event)   if msg =~ /\bdownload\b/i
  send_userlevel_screenshot(event) if msg =~ /\bscreen\s*shots*\b/i
  send_userlevel_scores(event)     if msg =~ /scores\b/i # matches 'highscores'
  send_random_userlevel(event)     if msg =~ /random/i
  #csv(event) if msg =~ /csv/i
end
