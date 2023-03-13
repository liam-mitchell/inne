require 'chunky_png' # for screenshot generation
require 'time'
require 'zlib'
#require 'oily_png' # more efficient screenshot generation (broken?)
include ChunkyPNG::Color
require_relative 'constants.rb'
require_relative 'utils.rb'
require_relative 'io.rb'
require_relative 'models.rb'

# Contains map data (tiles and objects) in a different table for performance reasons.
class UserlevelData < ActiveRecord::Base
end

class UserlevelTab < ActiveRecord::Base
end

class UserlevelAuthor < ActiveRecord::Base
  alias_attribute :akas, :userlevel_akas
  has_many :userlevels, foreign_key: :author_id
  has_many :userlevel_akas, foreign_key: :author_id

  # Parse a userlevel author based on a search term:
  # Integer:
  #   Search as the author ID
  # String:
  #   Search as part of the name, or optionally, also of the aka's (old names)
  # Number of results:
  #     0 - Raise error of no matches
  #     1 - Return author
  #   <20 - Print matches
  #  >=20 - Raise error of too many matches
  def self.parse(term, aliases = true)
    if term.is_a?(Integer)
      p = self.find(term) rescue nil
      raise "Userlevel author with ID #{verbatim(term)} not found." if p.nil?
      return p
    end
    raise "Couldn't parse userlevel author." if !term.is_a?(String)
    return nil if term.empty?
    p = self.where_like('name', term[0...16])
    case p.count
    when 0
      raise "No author found by the name #{verbatim(term)}." if !aliases
      p = UserlevelAka.where_like('name', term[0...16]).map(&:author).uniq
      case p.count
      when 0
        raise "No author found by the name (current or old) #{verbatim(term)}."
      when 1
        return p.first
      else
        raise "Too many author matches! (#{p.count}). Please refine author name." if p.count > 20
        matches = p.map{ |a| "#{"%6d" % a.id} - #{a.name}" }.join("\n")
        raise "Multiple matching authors found, please refine name or use author ID instead:\n#{format_block(matches)}"
      end
    when 1
      return p.first
    else
      raise "Too many author matches! (#{p.count}). Please refine author name." if p.count > 20
      matches = p.pluck(:id, :name).map{ |id, name| "#{"%6d" % id} - #{name}" }.join("\n")
      raise "Multiple matching authors found, please refine name or use author ID instead:\n#{format_block(matches)}"
    end
  end

  # Add an A.K.A. to the author (old name)
  def aka(str, time)
    str = INVALID_NAMES.include?(str) ? '' : str
    return if !self.akas.where(name: str).empty?
    UserlevelAka.create(author_id: self.id, name: str, date: time)
  end

  # Change author name, taking restrictions into account
  def rename(str, time = nil)
    str = INVALID_NAMES.include?(str) ? '' : str
    self.update(name: str)
    aka(str, !time.nil? ? time : Time.now.strftime(DATE_FORMAT_MYSQL))
  end
rescue RuntimeError
  raise
rescue
  nil
end

class UserlevelAka < ActiveRecord::Base
  alias_attribute :author, :userlevel_author
  belongs_to :userlevel_author, foreign_key: :author_id
end

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

  def self.retrieve_scores(full, mode = nil, author_id = nil)
    scores = full ? self.global : self.newest
    if !mode.nil? || !author_id.nil?
      scores = scores.joins("INNER JOIN userlevels ON userlevels.id = userlevel_scores.userlevel_id")
      if !mode.nil?
        scores = scores.where("userlevels.mode = #{mode.to_i}")
      end
      if !author_id.nil?
        scores = scores.where("userlevels.author_id = #{author_id.to_i}")
      end
    end
    scores
  end
end

class UserlevelPlayer < ActiveRecord::Base
  alias_attribute :scores, :userlevel_scores
  has_many :userlevel_scores, foreign_key: :player_id
  has_many :userlevel_histories, foreign_key: :player_id

  def newest(id = Userlevel.min_id)
    scores.where("userlevel_id >= #{id}")
  end

  def retrieve_scores(full = false, mode = nil, author_id = nil)
    query = full ? scores : newest
    if !mode.nil? || !author_id.nil?
      query = query.joins("INNER JOIN userlevels ON userlevels.id = userlevel_scores.userlevel_id")
      if !mode.nil?
        query = query.where("userlevels.mode = #{mode.to_i}")
      end
      if !author_id.nil?
        query = query.where("userlevels.author_id = #{author_id.to_i}")
      end
    end
    query
  end

  def range_s(rank1, rank2, ties, full = false, mode = nil, author_id = nil)
    t  = ties ? 'tied_rank' : 'rank'
    ss = retrieve_scores(full, mode, author_id).where("#{t} >= #{rank1} AND #{t} <= #{rank2}")
  end

  def range_h(rank1, rank2, ties, full = false, mode = nil, author_id = nil)
    range_s(rank1, rank2, ties, full, mode, author_id).group_by(&:rank).sort_by(&:first)
  end

  def top_ns(rank, ties, full = false, mode = nil, author_id = nil)
    range_s(0, rank - 1, ties, full, mode, author_id)
  end

  def top_n_count(rank, ties, full = false, mode = nil, author_id = nil)
    top_ns(rank, ties, full, mode, author_id).count
  end

  def range_n_count(a, b, ties, full = false, mode = nil, author_id = nil)
    range_s(a, b, ties, full, mode, author_id).count
  end

  def points(ties, full = false, mode = nil, author_id = nil)
    retrieve_scores(full, mode, author_id).sum(ties ? '20 - tied_rank' : '20 - rank')
  end

  def avg_points(ties, full = false, mode = nil, author_id = nil)
    retrieve_scores(full, mode, author_id).average(ties ? '20 - tied_rank' : '20 - rank')
  end

  def total_score(full = false, mode = nil, author_id = nil)
    retrieve_scores(full, mode, author_id).sum(:score).to_f / 60
  end

  def avg_lead(ties, full = false, mode = nil, author_id = nil)
    ss = top_ns(1, ties, full, mode, author_id)
    count = ss.length
    avg = count == 0 ? 0 : ss.map{ |s|
      entries = s.userlevel.scores.map(&:score)
      (entries[0].to_i - entries[1].to_i).to_f / 60.0
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
  alias_attribute :author, :userlevel_author
  has_many :userlevel_scores
  belongs_to :userlevel_author, foreign_key: :author_id
  enum mode: [:solo, :coop, :race]
  # Attributes:
  #   id           - ID of the userlevel in Metanet's database (and ours)
  #   author_id    - Map author user ID in Metanet's database (and ours)
  #   title        - Map title
  #   favs         - Number of favourites / ++s
  #   date         - Date of publishing, UTC times
  #   mode         - Playing mode [0 - Solo, 1 - Coop, 2 - Race]
  #   score_update - When the scores were last updated in the db
  #   map_update   - When the map properties (like favs) were last updated in the db
  #   tiles        - Tile data compressed in zlib, stored in userlevel_data
  #   objects      - Object data compressed in zlib, stored in userlevel_data
  # Note: For details about how map data is stored, see the encode_ and decode_ methods below.

  # 'pref' is the drawing preference for overlaps, the lower the higher
  # 'att' is the number of attributes they have in the old format (in the new one it's always 5)
  # 'old' is the ID in the old format, '-1' if it didn't exist
  # 'pal' is the index at which the colors of the object start in the palette image
  OBJECTS = {
    0x00 => { name: 'ninja',              pref:  4, att: 2, old:  0, pal:  6 },
    0x01 => { name: 'mine',               pref: 22, att: 2, old:  1, pal: 10 },
    0x02 => { name: 'gold',               pref: 21, att: 2, old:  2, pal: 14 },
    0x03 => { name: 'exit',               pref: 25, att: 4, old:  3, pal: 17 },
    0x04 => { name: 'exit switch',        pref: 20, att: 0, old: -1, pal: 25 },
    0x05 => { name: 'regular door',       pref: 19, att: 3, old:  4, pal: 30 },
    0x06 => { name: 'locked door',        pref: 28, att: 5, old:  5, pal: 31 },
    0x07 => { name: 'locked door switch', pref: 27, att: 0, old: -1, pal: 33 },
    0x08 => { name: 'trap door',          pref: 29, att: 5, old:  6, pal: 39 },
    0x09 => { name: 'trap door switch',   pref: 26, att: 0, old: -1, pal: 41 },
    0x0A => { name: 'launch pad',         pref: 18, att: 3, old:  7, pal: 47 },
    0x0B => { name: 'one-way platform',   pref: 24, att: 3, old:  8, pal: 49 },
    0x0C => { name: 'chaingun drone',     pref: 16, att: 4, old:  9, pal: 51 },
    0x0D => { name: 'laser drone',        pref: 17, att: 4, old: 10, pal: 53 },
    0x0E => { name: 'zap drone',          pref: 15, att: 4, old: 11, pal: 57 },
    0x0F => { name: 'chase drone',        pref: 14, att: 4, old: 12, pal: 59 },
    0x10 => { name: 'floor guard',        pref: 13, att: 2, old: 13, pal: 61 },
    0x11 => { name: 'bounce block',       pref:  3, att: 2, old: 14, pal: 63 },
    0x12 => { name: 'rocket',             pref:  8, att: 2, old: 15, pal: 65 },
    0x13 => { name: 'gauss turret',       pref:  9, att: 2, old: 16, pal: 69 },
    0x14 => { name: 'thwump',             pref:  6, att: 3, old: 17, pal: 74 },
    0x15 => { name: 'toggle mine',        pref: 23, att: 2, old: 18, pal: 12 },
    0x16 => { name: 'evil ninja',         pref:  5, att: 2, old: 19, pal: 77 },
    0x17 => { name: 'laser turret',       pref:  7, att: 4, old: 20, pal: 79 },
    0x18 => { name: 'boost pad',          pref:  1, att: 2, old: 21, pal: 81 },
    0x19 => { name: 'deathball',          pref: 10, att: 2, old: 22, pal: 83 },
    0x1A => { name: 'micro drone',        pref: 12, att: 4, old: 23, pal: 57 },
    0x1B => { name: 'alt deathball',      pref: 11, att: 2, old: 24, pal: 86 },
    0x1C => { name: 'shove thwump',       pref:  2, att: 2, old: 25, pal: 88 }
  }
  FIXED_OBJECTS = [0, 1, 2, 3, 4, 7, 9, 16, 17, 18, 19, 21, 22, 24, 25, 28]
  THEMES = [
    "acid",           "airline",         "argon",         "autumn",
    "BASIC",          "berry",           "birthday cake", "bloodmoon",
    "blueprint",      "bordeaux",        "brink",         "cacao",
    "champagne",      "chemical",        "chococherry",   "classic",
    "clean",          "concrete",        "console",       "cowboy",
    "dagobah",        "debugger",        "delicate",      "desert world",
    "disassembly",    "dorado",          "dusk",          "elephant",
    "epaper",         "epaper invert",   "evening",       "F7200",
    "florist",        "formal",          "galactic",      "gatecrasher",
    "gothmode",       "grapefrukt",      "grappa",        "gunmetal",
    "hazard",         "heirloom",        "holosphere",    "hope",
    "hot",            "hyperspace",      "ice world",     "incorporated",
    "infographic",    "invert",          "jaune",         "juicy",
    "kicks",          "lab",             "lava world",    "lemonade",
    "lichen",         "lightcycle",      "line",          "m",
    "machine",        "metoro",          "midnight",      "minus",
    "mir",            "mono",            "moonbase",      "mustard",
    "mute",           "nemk",            "neptune",       "neutrality",
    "noctis",         "oceanographer",   "okinami",       "orbit",
    "pale",           "papier",          "papier invert", "party",
    "petal",          "PICO-8",          "pinku",         "plus",
    "porphyrous",     "poseidon",        "powder",        "pulse",
    "pumpkin",        "QDUST",           "quench",        "regal",
    "replicant",      "retro",           "rust",          "sakura",
    "shift",          "shock",           "simulator",     "sinister",
    "solarized dark", "solarized light", "starfighter",   "sunset",
    "supernavy",      "synergy",         "talisman",      "toothpaste",
    "toxin",          "TR-808",          "tycho",         "vasquez",
    "vectrex",        "vintage",         "virtual",       "vivid",
    "void",           "waka",            "witchy",        "wizard",
    "wyvern",         "xenon",           "yeti"
  ]
  DEFAULT_PALETTE = "vasquez"
  PALETTE = ChunkyPNG::Image.from_file('images/palette.png')
  BORDERS = "100FF87E1781E0FC3F03C0FC3F03C0FC3F03C078370388FC7F87C0EC1E01C1FE3F13E"
  ROWS    = 23
  COLUMNS = 42
  DIM     = 44
  WIDTH   = DIM * (COLUMNS + 2)
  HEIGHT  = DIM * (ROWS + 2)

  def self.mode(mode)
    mode == -1 ? Userlevel : Userlevel.where(mode: mode)
  end

  def self.tab(qt, mode = -1)
    query = Userlevel::mode(mode)
    query = query.joins('INNER JOIN userlevel_tabs ON userlevel_tabs.userlevel_id = userlevels.id')
                 .where("userlevel_tabs.qt = #{qt}") if qt != 10
    query
  end

  def self.levels_uri(steam_id, qt = 10, page = 0, mode = 0)
    URI("https://dojo.nplusplus.ninja/prod/steam/query_levels?steam_id=#{steam_id}&steam_auth=&qt=#{qt}&mode=#{mode}&page=#{page}")
  end

  def self.search_uri(steam_id, search, page = 0, mode = 0)
    URI("https://dojo.nplusplus.ninja/prod/steam/search/levels?steam_id=#{steam_id}&steam_auth=&search=#{search}&mode=#{mode}&page=#{page}")
  end

  def self.serial(maps)
    maps.map{ |m|
      {
        id:     m.id,
        author: (m.author.name rescue ""),
        title:  m.title,
        date:   m.date.strftime(DATE_FORMAT_OUTTE),
        favs:   m.favs
      }
    }
  end

  def self.get_levels(qt = 10, page = 0, mode = 0)
    uri  = Proc.new { |steam_id, qt, page, mode| Userlevel::levels_uri(steam_id, qt, page, mode) }
    data = Proc.new { |data| data }
    err  = "error querying page #{page} of userlevels from category #{qt}"
    HighScore::get_data(uri, data, err, qt, page, mode)
  end

  # Parse binary file with userlevel collection received from N++'s server
  def self.parse(levels, update = false)
    # Parse header (48B)
    return nil if levels.size < 48
    header = {
      date:    levels[0...16],           # Rough date of query
      count:   _unpack(levels[16...20]), # Map count in this collection (<= 500)
      page:    _unpack(levels[20...24]), # Page number (>= 0)
      type:    _unpack(levels[24...28]), # Playable type (always 0, i.e., Level)
      qt:      _unpack(levels[28...32]), # Query type (0-36)
      mode:    _unpack(levels[32...36]), # Game mode (0 = Solo, 1 = Coop, 2 = Race, 3 = HC)
      cache:   _unpack(levels[36...40]), # Cache duration in seconds (usually 1200 or 5)
      max:     _unpack(levels[40...44]), # Max page size (usually 500 or 25)
      unknown: _unpack(levels[44...48])  # Unknown field (usually 0 or 5)
    }

    # Parse map headers (44B each)
    return nil if levels.size < 48 + 44 * header[:count]
    maps = levels[48 ... 48 + 44 * header[:count]].chars.each_slice(44).map { |h|
      {
        id:        _unpack(h[0...4], 'l<'),   # Userlevel ID
        author_id: _unpack(h[4...8], 'l<'),   # Author user ID (-1 if not found)
        author:    parse_str(h[8...24].join), # Author name, truncated to 16 chars
        favs:      _unpack(h[24...28], 'l<'), # ++ count
        date:      Time.strptime(h[28..-1].join, DATE_FORMAT_NPP).strftime(DATE_FORMAT_MYSQL)
      }
    }

    # Parse map data (variable length blocks)
    i = 0
    offset = 48 + header[:count] * 44
    while i < header[:count]
      # Parse mini-header (6B)
      break if levels.size < offset + 6
      len = _unpack(levels[offset...offset + 4])                 # Block length (4B)
      maps[i][:count] = _unpack(levels[offset + 4...offset + 6]) # Object count (2B)

      # Parse compressed data
      break if levels.size < offset + len
      map = Zlib::Inflate.inflate(levels[offset + 6...offset + len])
      maps[i][:title] = parse_str(map[30...158])
      maps[i][:tiles] = map[176...1142].bytes.each_slice(42).to_a
      maps[i][:objects] = map[1222..-1].bytes.each_slice(5).to_a
      offset += len
      i += 1
    end

    # Update database
    result = []
    ActiveRecord::Base.transaction do
      maps.each{ |map|
        if update
          # Userlevel object
          entry = Userlevel.find_or_create_by(id: map[:id]).update(
            title:     map[:title],
            author_id: map[:author_id],
            favs:      map[:favs],
            date:      map[:date],
            mode:      header[:mode]
          )
          # Userlevel author
          UserlevelAuthor.find_or_create_by(id: map[:author_id]).rename(map[:author], map[:date])
          # Userlevel map data
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

  # Dump 48 byte header used by the game for userlevel queries
  def self.query_header(count, cat, mode)
    mcount  = QUERY_LIMIT_SOFT
    header  = Time.now.strftime(DATE_FORMAT_NPP) # Date of query  (16B)
    header += _pack(count,  4)                   # Map count      ( 4B)
    header += _pack(0,      4)                   # Query page     ( 4B)
    header += _pack(0,      4)                   # Type           ( 4B)
    header += _pack(cat,    4)                   # Query category ( 4B)
    header += _pack(mode,   4)                   # Game mode      ( 4B)
    header += _pack(5,      4)                   # Cache duration ( 4B)
    header += _pack(mcount, 4)                   # Max page size  ( 4B)
    header += _pack(0,      4)                   # ?              ( 4B)
    header
  end

  # Dump binary file containing a collection of userlevels using the format
  # of query results that the game utilizes
  # (see self.parse for documentation of this format)
  # TODO: Add more integrity checks (category...)
  def self.dump_query(maps, cat, mode)
    raise "Some of the queried userlevels have an incorrect game mode." if !maps.index{ |m| MODES.invert[m.mode] != mode }.nil?
    raise "Too many queried userlevels." if maps.size > QUERY_LIMIT_HARD
    header  = query_header(maps.size, cat, mode)
    headers = maps.map{ |m| m.dump_header }.join
    data    = maps.map{ |m| m.dump_data }.join
    header + headers + data
  end

  # Updates position of userlevels in several lists (best, top weekly, featured, hardest...)
  # For this, one field per list is used, and most userlevels have a value of NULL here
  # A different table to store these relationships would be better storage-wise, but would
  # severely limit querying flexibility.
  def self.parse_tabs(levels)
    return false if levels.nil? || levels.size < 48
    count  = parse_int(levels[16..19])
    page   = parse_int(levels[20..23])
    qt     = parse_int(levels[28..31])
    mode   = parse_int(levels[32..35])
    tab    = USERLEVEL_TABS[qt][:name] rescue nil
    return false if tab.nil?

    ActiveRecord::Base.transaction do
      ids = levels[48 .. 48 + 44 * count - 1].scan(/./m).each_slice(44).to_a.each_with_index{ |l, i|
        index = page * PART_SIZE + i
        return false if USERLEVEL_TABS[qt][:size] != -1 && index >= USERLEVEL_TABS[qt][:size]
        print("Updating #{MODES[mode].downcase} #{USERLEVEL_TABS[qt][:name]} map #{index + 1} / #{USERLEVEL_TABS[qt][:size]}...".ljust(80, " ") + "\r")
        UserlevelTab.find_or_create_by(mode: mode, qt: qt, index: index).update(userlevel_id: parse_int(l[0..3]))
        return false if USERLEVEL_TABS[qt][:size] != -1 && index + 1 >= USERLEVEL_TABS[qt][:size] # Seems redundant, but prevents downloading a file for nothing
      }
    end
    return true
  rescue => e
    print(e)
    return false
  end

  # Returns true if the page is full, indicating there are more pages
  def self.update_relationships(qt = 11, page = 0, mode = 0)
    return false if !USERLEVEL_TABS.select{ |k, v| v[:update] }.keys.include?(qt)
    levels = get_levels(qt, page, mode)
    return parse_tabs(levels) && parse_int(levels[16..19]) == PART_SIZE
  end

  def self.browse(qt = 10, page = 0, mode = 0, update = false)
    levels = get_levels(qt, page, mode)
    parse(levels, update)
  end

  def self.search(search = "", page = 0, mode = 0, update = false)
    levels = get_search(search, page, mode)
    parse(levels, update)
  end

  # Produces the SQL order string, used when fetching maps from the db
  def self.sort(order = "", invert = false)
    return "" if !order.is_a?(String)
     # possible spellings for each field, to be used for sorting or filtering
     # doesn't include plurals (except "favs", read next line) because we "singularize" later
     # DO NOT CHANGE FIRST VALUE (its also the column name)
    fields = {
      :id     => ["id", "map id", "map_id", "level id", "level_id"],
      :title  => ["title", "name"],
      :author => ["author", "player", "user", "person", "mapper"],
      :date   => ["date", "time", "datetime", "moment", "day", "period"],
      :favs   => ["favs", "fav", "++", "++'", "favourite", "favorite"]
    }
    inverted = [:date, :favs] # the order of these fields will be reversed by default
    fields.each{ |k, v|
      if v.include?(order.strip.singularize)
        order = k
        break
      end
    }
    return "" if !order.is_a?(Symbol)
    # sorting by date and id is equivalent, sans the direction
    str = order == :date ? "id" : fields[order][0]
    if inverted.include?(order) ^ invert then str += " DESC" end
    str
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

  # find the optimal score / amount of whatever rankings or stat
  def self.find_max(rank, global, mode = nil, author_id = nil)
    case rank
    when :points
      query = global ? self.global : self.newest
      query = query.where(mode: mode) if !mode.nil?
      query = query.where(author_id: author_id) if !author_id.nil?
      query = query.count * 20
      global ? query : [query, USERLEVEL_REPORT_SIZE * 20].min
    when :avg_points
      20
    when :avg_rank
      0  
    when :maxable
      self.ties(nil, false, global, true, mode, author_id)
    when :maxed
      self.ties(nil, true, global, true, mode, author_id)
    when :score
      query = UserlevelScore.retrieve_scores(global, mode, author_id)
      query.where(rank: 0).sum(:score).to_f / 60.0
    else
      query = global ? self.global : self.newest       
      query = query.where(mode: mode) if !mode.nil?
      query = query.where(author_id: author_id) if !author_id.nil?
      query = query.count
      global ? query : [query, USERLEVEL_REPORT_SIZE].min
    end
  end

  def self.find_min(full, mode = nil, author_id = nil)
    limit = 0
    if full
      if author_id.nil?
        limit = MIN_G_SCORES
      else
        limit = MIN_U_SCORES
      end
    else
      if author_id.nil?
        limit = MIN_U_SCORES
      else
        limit = 0
      end
    end
    limit
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
  # @par mode:      0 = Solo, 1 = Coop, 2 = Race, nil = All
  # @par author_id: Include only maps by this author
  def self.ties(player_id = nil, maxed = false, full = false, count = false, mode = nil, author_id = nil)
    bench(:start) if BENCHMARK
    scores = UserlevelScore.retrieve_scores(full, mode, author_id)
    # retrieve most tied for 0th leves
    ret = scores.where(tied_rank: 0)
                .group(:userlevel_id)
                .order(!maxed ? 'count(userlevel_scores.id) desc' : '', :userlevel_id)
                .having('count(userlevel_scores.id) >= 3')
                .having(!player_id.nil? ? 'amount = 0' : '')
                .pluck('userlevel_id', 'count(userlevel_scores.id)', !player_id.nil? ? "count(if(player_id = #{player_id}, player_id, NULL)) AS amount" : '1')
                .map{ |s| s[0..1] }
                .to_h
    # retrieve total score counts for each level (to compare against the tie count and determine maxes)
    counts = scores.where(userlevel_id: ret.keys)
                   .group(:userlevel_id)
                   .order('count(userlevel_scores.id) desc')
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

  def self.rank(type, ties = false, par = nil, full = false, global = false, author_id = nil)
    scores = global ? UserlevelScore.global : UserlevelScore.newest
    if !author_id.nil?
      ids = Userlevel.where(author_id: author_id).pluck(:id)
      scores = scores.where(userlevel_id: ids)
    end

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
                     .having("count(player_id) >= #{find_min(global, nil, author_id)}")
                     .order("avg(#{ties ? "20 - tied_rank" : "20 - rank"}) desc")
                     .average(ties ? "20 - tied_rank" : "20 - rank")
    when :avg_rank
      scores = scores.select("count(player_id)")
                     .group(:player_id)
                     .having("count(player_id) >= #{find_min(global, nil, author_id)}")
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
    scores = scores.map{ |p, c| [players[p], c] }
    scores.reject!{ |p, c| c <= 0  } unless type == :avg_rank
    scores
  end

  # technical
  def self.sanitize(string, par)
    sanitize_sql_for_conditions([string, par])
  end

  def self.where_like(query, field, str)
    query.where("#{field} LIKE (?)", "%" + sanitize_sql_like(str) + "%")
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
  # If query is true, then the format for userlevel query files is used (slightly
  # different header, shorter)
  def convert(query = false)
    objs = self.objects
    # HEADER
    data = ""
    if !query
      data << ("\x00" * 4).force_encoding("ascii-8bit") # magic number ?
      data << _pack(1230 + 5 * objs.size, 4)            # Filesize
    end
    data << ("\xFF" * 4).force_encoding("ascii-8bit")   # Level ID (unset)
    data << _pack(Userlevel.modes[self.mode], 4)        # Game mode
    data << _pack(37, 4)                                # QT (unset, max is 36)
    data << (query ? _pack(self.author_id, 4) : ("\xFF" * 4).force_encoding("ascii-8bit"))
    data << ("\x00" * 4).force_encoding("ascii-8bit")   # Fav count (unset)
    data << ("\x00" * 10).force_encoding("ascii-8bit")  # Date SystemTime (unset)
    data << self.title[0..126].ljust(128,"\x00").force_encoding("ascii-8bit") # map title
    data << ("\x00" * 16).force_encoding("ascii-8bit")  # Author name (unset)
    data << ("\x00" * 2).force_encoding("ascii-8bit")   # Padding

    # MAP DATA
    tile_data = self.tiles.flatten.map{ |b| [b.to_s(16).rjust(2,"0")].pack('H*')[0] }.join
    object_counts = [0] * 40
    object_data = ""
    objs.each{ |o| object_counts[o[0]] += 1 }
    objs.group_by{ |o| o[0] }
    object_counts[7] = 0
    object_counts[9] = 0
    object_counts = object_counts.map{ |c| _pack(c, 2) }.join
    object_data = objs.map{ |o| o.map{ |b| [b.to_s(16).rjust(2,"0")].pack('H*')[0] }.join }.join
=begin # Don't remove, as this is the code that works if objects aren't already sorted in the database
    OBJECTS.sort_by{ |id, entity| id }.each{ |id, entity|
      if ![7,9].include?(id) # ignore door switches for counting
        object_counts << objs.select{ |o| o[0] == id }.size.to_s(16).rjust(4,"0").scan(/../).reverse.map{ |b| [b].pack('H*')[0] }.join
      else
        object_counts << "\x00\x00"
      end
      if ![6,7,8,9].include?(id) # doors must once again be treated differently
        object_data << objs.select{ |o| o[0] == id }.map{ |o| o.map{ |b| [b.to_s(16).rjust(2,"0")].pack('H*')[0] }.join }.join
      elsif [6,8].include?(id)
        doors = objs.select{ |o| o[0] == id }.map{ |o| o.map{ |b| [b.to_s(16).rjust(2,"0")].pack('H*')[0] }.join }
        switches = objs.select{ |o| o[0] == id + 1 }.map{ |o| o.map{ |b| [b.to_s(16).rjust(2,"0")].pack('H*')[0] }.join }
        object_data << doors.zip(switches).flatten.join
      end
    }
=end
    data << (tile_data + object_counts.ljust(80, "\x00") + object_data).force_encoding("ascii-8bit")
    data
  end

  # Generate compressed map dump in the format the game uses when browsing
  def dump_data
    block  = self.convert(true)
    dblock = Zlib::Deflate.deflate(block, 9)
    ocount = (block.size - 0xB0 - 966 - 80) / 5
    data  = _pack(dblock.size + 6, 4) # Length of full data block (4B)
    data += _pack(ocount,          2) # Object count              (2B)
    data += dblock                    # Zlib-compressed map data  (?B)
    data
  end

  # Generate 44 byte map header of the dump above
  def dump_header
    header  = _pack(id, 4)                                          # Userlevel ID ( 4B)
    header += _pack(author_id, 4)                                   # User ID      ( 4B)
    header += (author.name.to_s[0..15] rescue "").ljust(16, "\x00") # User name    (16B)
    header += _pack(favs, 4)                                        # Map ++'s     ( 4B)
    header += date.strftime(DATE_FORMAT_NPP).ljust(16, "\x00")      # Map date     (16B)
    header
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
    bench(:start) if BENCHMARK
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
    bench(:step) if BENCHMARK
    image.to_blob
  end
end

# <---------------------------------------------------------------------------->
# <---                           MESSAGES                                   --->
# <---------------------------------------------------------------------------->

def format_userlevels(maps, page)
  return "" if maps.size == 0
  maps = Userlevel::serial(maps)
  # Calculate required column padding
  max_padding = {n: 6, id: 6, title: 30, author: 16, date: 16, favs: 4 }
  min_padding = {n: 1, id: 2, title:  5, author:  6, date: 16, favs: 2 }
  def_padding = {n: 3, id: 6, title: 25, author: 16, date: 16, favs: 2 }
  if !maps.nil? && !maps.empty?
    n_padding =      [ [ (PAGE_SIZE * (page - 1) + maps.size).to_s.length,  max_padding[:n]     ].min, min_padding[:n]      ].max
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
  output  = "%-#{padding[:n]}s "      % "N"
  output += "%-#{padding[:id]}s "     % "ID"
  output += "%-#{padding[:title]}s "  % "TITLE"
  output += "%-#{padding[:author]}s " % "AUTHOR"
  output += "%-#{padding[:date]}s "   % "DATE"
  output += "%-#{padding[:favs]}s"    % "++"
  output += "\n"
  #output += "-" * (padding.inject(0){ |sum, pad| sum += pad[1] } + padding.size - 1) + "\n"

  # Print levels
  if maps.nil? || maps.empty?
    output += " " * (padding.inject(0){ |sum, pad| sum += pad[1] } + padding.size - 1) + "\n"
  else
    maps.each_with_index{ |m, i|
      line = "%#{padding[:n]}.#{padding[:n]}s " % (PAGE_SIZE * (page - 1) + i + 1).to_s
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
  format_block(output)
end

# The next function queries userlevels from the database based on a number of
# parameters, like the title, the author, the tab and the mode, as well as
# allowing for arbitrary orders.
# 
# Parameters:
#   The parameters are only used when the function has been called by interacting
#   with a pre-existing post, in which case we parse the header of the message as
#   though it was a user command, to figure out the original query, and then modify
#   it by the values of the parameters (e.g. incrementing the page).
#
#   Therefore, be CAREFUL when modifying the header of the message. It must still
#   be a valid regex command containing all necessary info.
#
# Socket:
#   The socket parameter is an exception to the above. It's used when the query has
#   been received from CUSE rather than Discord, in which case, instead of printing
#   the map list, we return the maps so they can be dumped and sent back to CUSE.
def send_userlevel_browse(event, page: nil, order: nil, tab: nil, mode: nil, query: nil, socket: nil)
  
  # <------ PARSE all message elements ------>

  bench(:start) if BENCHMARK
  # Determine whether this is the initial query (new post) or an interaction
  # query (edit post).
  initial = page.nil? && order.nil? && tab.nil? && mode.nil?
  reset_page = page.nil? && !initial
  if !socket.nil?
    msg = socket
  else
    if !query.nil?
      msg = ""
    else
      msg = fetch_message(event, initial)
    end
  end
  h      = parse_order(msg, order) # Updates msg
  msg    = h[:msg]
  order  = h[:order]
  invert = h[:invert]
  if query.nil?
    search, author, msg = parse_title_and_author(msg, false)
    search = unescape(search) if search.is_a?(String)
    author = unescape(author) if author.is_a?(String)
  else
    search = query[:title]
    author = query[:author]
  end
  page   = parse_page(msg, page, reset_page, !event.nil? ? event.message.components : nil)
  mode   = MODES.select{ |k, v| v == (mode || parse_mode(msg, !socket.nil?)) }.keys.first

  # Determine the category / tab
  cat = 10 # newest
  USERLEVEL_TABS.each{ |qt, v| cat = qt if tab.nil? ? !!(msg =~ /#{v[:name]}/i) : tab == v[:name] }
  is_tab = USERLEVEL_TABS.select{ |k, v| v[:update] }.keys.include?(cat)

  #<------ FETCH userlevels ------>

  pagesize = !socket.nil? ? QUERY_LIMIT_SOFT : PAGE_SIZE
  # Filter userlevels
  if query.nil?
    query   = Userlevel::tab(cat, mode)
    query   = query.where(Userlevel.sanitize("author LIKE ?", "%" + author[0...16] + "%")) if !author.empty?
    query   = query.where(Userlevel.sanitize("title LIKE ?", "%" + search[0...128] + "%")) if !search.empty?
  else
    query   = query[:query]
  end
  # Compute count, page number, total pages, and offset
  count     = query.count
  pag       = compute_pages(count, page, pagesize)
  # Order userlevels
  order_str = Userlevel::sort(order, invert)
  query     = !order_str.empty? ? query.order(order_str) : (is_tab ? query.order("`index` ASC") : query.order("id DESC"))
  # Fetch userlevels
  ids       = query.offset(pag[:offset]).limit(pagesize).pluck(:id)
  maps      = query.where(id: ids).all.to_a
  return { maps: maps, mode: mode, cat: cat } if !socket.nil?

  # <------ FORMAT message ------>

  # CAREFUL reformatting the first two lines of the output message (the header),
  # since they are used for parsing the message. When someone interacts with it,
  # either by pressing a button or making a selection in the menu, we need to
  # modify the query and edit the message. We use the header to figure out what
  # the original query was, by parsing it exactly as though it were a user
  # message, so it needs to have a format compatible with the regex we use to
  # parse commands. I know, genius implementation.
  output = "Browsing #{USERLEVEL_TABS[cat][:name]}#{mode == -1 ? '' : ' ' + MODES[mode]} maps"
  output += " by `#{author[0..63]}`" if !author.empty?
  output += " for `#{search[0..63]}`" if !search.empty?
  output += " sorted by #{invert ? "-" : ""}#{!order_str.empty? ? order : (is_tab ? "default" : "date")}."
  output += format_userlevels(maps, pag[:page])
  output += count == 0 ? "\nNo results :shrug:" : "Total results: **#{count}**."
  bench(:step) if BENCHMARK

  # <------ SEND message ------>

  craft_userlevel_browse_msg(
    event,
    output,
    page:  pag[:page],
    pages: pag[:pages],
    order: order_str,
    tab:   USERLEVEL_TABS[cat][:name],
    mode:  MODES[mode],
    edit:  !initial,
    int:   !(initial && count == 0)
  )
rescue => e
  err(e)
  puts(e.backtrace)
  err_str = "An error happened, try again, if it keeps failing, contact the botmeister."
  if !socket.nil?
    log("Error socketing userlevel query.")
  else
    if initial
      event << err_str
    else
      event.channel.send_message(err_str)
    end
  end
end

# Wrapper for functions that need to be execute in a single userlevel
# (e.g. download, screenshot, scores...)
# This will parse the query, find matches, and:
#   1) If there are no matches, display an error
#   2) If there is 1 match, execute function passed in the block
#   3) If there are multiple matches, execute the browse function
# We pass in the msg (instead of extracting it from the event)
# because it might've been modified by the caller function already.
def send_userlevel_individual(event, msg, &block)
  map = parse_userlevel(msg)
  case map[:count]
  when 0
    event << map[:msg]
    return
  when 1
    yield(map)
  else
    event.send_message(map[:msg])
    sleep(0.250) # Prevent rate limiting
    send_userlevel_browse(event, query: map)
  end
end

def send_userlevel_download(event)
  msg = clean_userlevel_message(event.content)
  msg = remove_word_first(msg, 'download')
  send_userlevel_individual(event, msg){ |map|
    output = "Downloading userlevel `" + map[:query].title + "` with ID `" + map[:query].id.to_s
    output += "` by `" + (map[:query].author.name.empty? ? " " : map[:query].author.name) + "` on " + Time.now.to_s + ".\n"
    event << output
    send_file(event, map[:query].convert, map[:query].id.to_s, true)
  }
end

# We can pass the actual level instead of parsing it from the message
# This is used e.g. by the random userlevel function
def send_userlevel_screenshot(event, userlevel = nil)
  msg = clean_userlevel_message(event.content)
  msg = remove_word_first(msg, 'screenshot')
  h = parse_palette(msg)
  send_userlevel_individual(event, h[:msg]){ |map|
    output = "#{h[:error]}Screenshot of userlevel `#{map[:query].title}` with ID `#{map[:query].id.to_s}"
    output += "` by `#{map[:query].author.name.empty? ? " " : map[:query].author.name}` using palette `"
    output += "#{h[:palette]}` on #{Time.now.to_s}.\n"
    event << output
    send_file(event, map[:query].screenshot(h[:palette]), map[:query].id.to_s + ".png", true)
  }
end

def send_userlevel_scores(event)
  msg = clean_userlevel_message(event.content)
  msg = remove_word_first(msg, 'scores')
  send_userlevel_individual(event, msg){ |map|
    output = "Scores of userlevel `" + map[:query].title + "` with ID `" + map[:query].id.to_s
    output += "` by `" + (map[:query].author.name.empty? ? " " : map[:query].author.name) + "` on " + Time.now.to_s + ".\n"
    event << output + "```" + map[:query].format_scores + "```"
  }
end

def send_userlevel_rankings(event)
  msg       = event.content
  rank      = parse_rank(msg) || 1
  rank      = 1 if rank < 0
  rank      = 20 if rank > 20
  ties      = parse_ties(msg)
  full      = parse_full(msg)
  global    = parse_global(msg)
  author    = parse_author(msg, false)
  author_id = !author.nil? ? author.id : nil
  type      = ""

  if msg =~ /average/i
    if msg =~ /point/i
      top     = Userlevel.rank(:avg_points, ties, nil, full, global, author_id)
      type    = "average points"
      max     = Userlevel.find_max(:avg_points, global, nil, author_id)
    elsif msg =~ /lead/i
      top     = Userlevel.rank(:avg_lead, nil, nil, full, global, author_id)
      type    = "average lead"
      max     = nil
    else
      top     = Userlevel.rank(:avg_rank, ties, nil, full, global, author_id)
      type    = "average rank"
      max     = Userlevel.find_max(:avg_rank, global, nil, author_id)
    end
  elsif msg =~ /point/i
    top       = Userlevel.rank(:points, ties, nil, full, global, author_id)
    type      = "total points"
    max       = Userlevel.find_max(:points, global, nil, author_id)
  elsif msg =~ /score/i
    top       = Userlevel.rank(:score, nil, nil, full, global, author_id)
    type      = "total score"
    max       = Userlevel.find_max(:score, global, nil, author_id)
  elsif msg =~ /tied/i
    top       = Userlevel.rank(:tied, ties, rank - 1, full, global, author_id)
    type      = "tied #{format_rank(rank)}"
    max       = Userlevel.find_max(:rank, global, nil, author_id)
  else
    top       = Userlevel.rank(:rank, ties, rank - 1, full, global, author_id)
    type      = format_rank(rank)
    max       = Userlevel.find_max(:rank, global, nil, author_id)
  end

  score_padding = top.map{ |r| r[1].to_i.to_s.length }.max
  name_padding  = top.map{ |r| r[0].name.length }.max
  format        = top[0][1].is_a?(Integer) ? "%#{score_padding}d" : "%#{score_padding + 4}.3f"
  top           = "```" + top.each_with_index
                  .map{ |p, i| "#{"%02d" % i}: #{format_string(p[0].name, name_padding)} - #{format % p[1]}" }
                  .join("\n") + "```"
  top.concat("Minimum number of scores required: #{Userlevel.find_min(global, nil, author_id)}") if msg =~ /average/i

  full   = format_full(full)
  global = format_global(global)
  ties   = format_ties(ties)
  header = "Userlevel #{full} #{global} #{type} #{ties} rankings #{format_author(author)} #{format_max(max)} #{format_time}:".squish
  length = header.length + top.length
  event << header
  length < DISCORD_LIMIT ? event << top : send_file(event, top[3..-4], "userlevel-rankings.txt", false)
end

def send_userlevel_count(event)
  msg       = event.content
  player    = parse_player(msg, event.user.name, true)
  author    = parse_author(msg, false)
  author_id = !author.nil? ? author.id : nil
  full      = parse_global(msg)
  rank      = parse_rank(msg) || 20
  bott      = parse_bottom_rank(msg) || 0
  ind       = nil
  dflt      = parse_rank(msg).nil? && parse_bottom_rank(msg).nil?
  type      = parse_type(msg)
  tabs      = parse_tabs(msg)
  ties      = parse_ties(msg)
  tied      = parse_tied(msg)
  20.times.each{ |r| ind = r if !!(msg =~ /\b#{r.ordinalize}\b/i) }

  # If no range is provided, default to 0th count
  if dflt
    bott = 0
    rank = 1
  end

  # If an individual rank is provided, the range has width 1
  if !ind.nil?
    bott = ind
    rank = ind + 1
  end

  # The range must make sense
  if bott >= rank
    event << "You specified an empty range! (#{bott.ordinalize}-#{(rank - 1).ordinalize})"
    return
  end

  # Retrieve score count in specified range
  if tied
    count = player.range_n_count(bott, rank - 1, true, full, nil, author_id) - player.range_n_count(bott, rank - 1, type, tabs, false, full, nil, author_id)
  else
    count = player.range_n_count(bott, rank - 1, ties, full, nil, author_id)
  end

  # Format range
  if bott == rank - 1
    header = "#{bott.ordinalize}"
  elsif bott == 0
    header = format_rank(rank)
  elsif rank == 20
    header = format_bottom_rank(bott)
  else
    header = "#{bott.ordinalize}-#{(rank - 1).ordinalize}"
  end

  max  = Userlevel.find_max(:rank, full, nil, author_id)
  ties = format_ties(ties)
  tied = format_tied(tied)
  full = format_global(full)
  event << "#{player.name} has #{count} out of #{max} #{full} #{tied} #{header} scores #{ties} #{format_author(author)}.".squish
end

def send_userlevel_points(event)
  msg       = event.content
  player    = parse_player(msg, event.user.name, true)
  author    = parse_author(msg, false)
  author_id = !author.nil? ? author.id : nil
  ties      = parse_ties(msg)
  full      = parse_global(msg)
  max       = Userlevel.find_max(:points, full, nil, author_id)
  points    = player.points(ties, full, nil, author_id)
  ties      = format_ties(ties)
  full      = format_global(full)
  event << "#{player.name} has #{points} out of #{max} #{full} userlevel points #{ties} #{format_author(author)}.".squish
end

def send_userlevel_avg_points(event)
  msg       = event.content
  player    = parse_player(msg, event.user.name, true)
  author    = parse_author(msg, false)
  author_id = !author.nil? ? author.id : nil
  ties      = parse_ties(msg)
  full      = parse_global(msg)
  avg       = player.avg_points(ties, full, nil, author_id)
  ties      = format_ties(ties)
  full      = format_global(full)
  event << "#{player.name} has #{"%.3f" % avg} average #{full} userlevel points #{ties} #{format_author(author)}.".squish
end

def send_userlevel_avg_rank(event)
  msg       = event.content
  player    = parse_player(msg, event.user.name, true)
  author    = parse_author(msg, false)
  author_id = !author.nil? ? author.id : nil
  ties      = parse_ties(msg)
  full      = parse_global(msg)
  avg       = 20 - player.avg_points(ties, full, nil, author_id)
  ties      = format_ties(ties)
  full      = format_global(full)
  event << "#{player.name} has an average #{"%.3f" % avg} #{full} userlevel rank #{ties} #{format_author(author)}.".squish
end

def send_userlevel_total_score(event)
  msg       = event.content
  player    = parse_player(msg, event.user.name, true)
  author    = parse_author(msg, false)
  author_id = !author.nil? ? author.id : nil
  full      = parse_global(msg)
  max       = Userlevel.find_max(:score, full, nil, author_id)
  score     = player.total_score(full, nil, author_id)
  full      = format_global(full)
  event << "#{player.name}'s total #{full} userlevel score is #{"%.3f" % score} out of #{"%.3f" % max} #{format_author(author)}.".squish
end

def send_userlevel_avg_lead(event)
  msg       = event.content
  player    = parse_player(msg, event.user.name, true)
  author    = parse_author(msg, false)
  author_id = !author.nil? ? author.id : nil
  ties      = parse_ties(msg)
  full      = parse_global(msg)
  avg       = player.avg_lead(ties, full, nil, author_id)
  ties      = format_ties(ties)
  full      = format_global(full)
  event << "#{player.name} has an average #{"%.3f" % avg} #{full} userlevel 0th lead #{ties} #{format_author(author)}.".squish
end

def send_userlevel_list(event)
  msg       = event.content
  player    = parse_player(msg, event.user.name, true)
  author    = parse_author(msg, false)
  author_id = !author.nil? ? author.id : nil
  rank      = parse_rank(msg) || 20
  bott      = parse_bottom_rank(msg) || 0
  ties      = parse_ties(msg)
  full      = parse_global(msg)
  if rank == 20 && bott == 0 && !!msg[/0th/i]
    rank = 1
    bott = 0
  end
  all = player.range_h(bott, rank - 1, ties, full, nil, author_id)

  res = all.map{ |rank, scores|
    rank.to_s.rjust(2, '0') + ":\n" + scores.map{ |s|
      "  #{HighScore.format_rank(s.rank)}: [#{s.userlevel.id.to_s.rjust(6)}] #{s.userlevel.title} (#{"%.3f" % [s.score.to_f / 60.0]})"
    }.join("\n")
  }.join("\n")
  send_file(event, res, "#{full ? "global-" : ""}userlevel-scores-#{player.name}.txt")
end

def send_userlevel_stats(event)
  msg       = event.content
  player    = parse_player(msg, event.user.name, true)
  author    = parse_author(msg, false)
  author_id = !author.nil? ? author.id : nil
  ties      = parse_ties(msg)
  full      = parse_global(msg)
  counts    = player.range_h(0, 19, ties, full, nil, author_id).map{ |rank, scores| [rank, scores.length] }

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
  event << "#{full.capitalize} userlevels highscoring stats for #{player.name} #{format_author(author)} #{format_time}:".squish
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
  event << "#{full.capitalize} userlevels #{!player.nil? ? "owned by #{player.name}" : ""} with the #{spread} spread between 0th and #{rank}:".squish
  event << format_block(spreads)
end

def send_userlevel_maxed(event)
  msg       = event.content
  player    = parse_player(msg, nil, true, true, false)
  author    = parse_author(msg, false)
  author_id = !author.nil? ? author.id : nil
  full      = parse_global(msg)
  ties      = Userlevel.ties(player.nil? ? nil : player.id, true, full, false, nil, author_id)
                       .select { |s| s[1] == s[2] }
                       .map { |s| "#{"%6d" % s[0].id} - #{"%6d" % s[0].author_id} - #{format_string(s[3])}" }
  count  = ties.count{ |s| s.length > 1 }
  player = player.nil? ? "" : " without " + player.name
  full   = format_global(full)
  block  = "    ID - Author - Player\n#{ties.join("\n")}"
  str = "Potentially maxed #{full} userlevels (with all scores tied for 0th) #{format_time} #{player} #{format_author(author)}:".squish
  count <= 20 ? str += "```#{block}```" : send_file(event, block, "maxed-userlevels.txt", false)
  str += "There's a total of #{count} potentially maxed userlevels."
  event << str
end

def send_userlevel_maxable(event)
  msg       = event.content
  player    = parse_player(msg, nil, true, true, false)
  author    = parse_author(msg, false)
  author_id = !author.nil? ? author.id : nil
  full      = parse_global(msg)
  ties      = Userlevel.ties(player.nil? ? nil : player.id, false, full, false, nil, author_id)
                       .select { |s| s[1] < s[2] }
                       .sort_by { |s| -s[1] }
  count = ties.count
  ties  = ties.take(NUM_ENTRIES)
               .map { |s| "#{"%6s" % s[0].id} - #{"%4d" % s[1]} - #{"%6d" % s[0].author_id} - #{format_string(s[3])}" }
  player = player.nil? ? "" : " without " + player.name
  full   = format_global(full)
  str  = "#{full.capitalize} userlevels with the most ties for 0th #{format_time} #{player} #{format_author(author)}:".squish
  str += "```    ID - Ties - Author - Player\n#{ties.join("\n")}```"
  str += "There's a total of #{count} maxable userlevels."
  event << str
end

def send_random_userlevel(event)
  msg       = event.content
  author    = parse_author(msg, false)
  author_id = !author.nil? ? author.id : nil
  amount    = [(msg[/\d+/] || 1).to_i, PAGE_SIZE].min
  mode      = parse_mode(msg, true)
  full      = !parse_newest(msg)
  maps      = full ? Userlevel.global : Userlevel.newest

  maps = maps.where(mode: mode.to_sym)
  maps = maps.where(author_id: author_id) if !author_id.nil?
  maps = maps.sample(amount)  

  if amount > 1
    event << "Random selection of #{amount} #{mode} #{format_global(full)} userlevels #{!author.nil? ? "by #{author.name}" : ""}:".squish
    event << format_userlevels(maps, 0)
  else
    send_userlevel_screenshot(event, maps.first)
  end
end

def send_userlevel_mapping_summary(event)
  # Parse message parameters
  msg       = event.content
  author    = UserlevelAuthor.parse(parse_userlevel_both(msg))
  author_id = !author.nil? ? author.id : nil
  full      = parse_global(msg)
  mode      = parse_mode(msg, false, true)

  # Fetch userlevels
  maps = Userlevel.global
  maps = maps.where(mode: mode.to_sym) if !mode.nil?
  maps = maps.where(author_id: author_id) if !author_id.nil?
  count = maps.count

  # Perform summary
  event << "Userlevel mapping summary#{" for #{author.name}" if !author.nil?}:```"
  event << "Maps:           #{count}"
  if author.nil?
    authors  = maps.distinct.count(:author_id)
    prolific = maps.group(:author_id).order("count(id) desc").count(:id).first
    popular  = maps.group(:author_id).order("sum(favs) desc").sum(:favs).first
    refined  = maps.group(:author_id).order("avg(favs) desc").average(:favs).first
    event << "Authors:        #{authors}"
    event << "Maps / author:  #{"%.3f" % (count.to_f / authors)}"
    event << "Most maps:      #{prolific.last} (#{Userlevel.find_by(author_id: prolific.first).author.name})"
    event << "Most ++'s:      #{popular.last} (#{Userlevel.find_by(author_id: popular.first).author.name})"
    event << "Most avg ++'s:  #{"%.3f" % refined.last} (#{Userlevel.find_by(author_id: refined.first).author.name})"
  end
  if !maps.empty?
    first = maps.order(:id).first
    event << "First map:      #{first.date.strftime(DATE_FORMAT_OUTTE)} (#{first.id})"
    last = maps.order(id: :desc).first
    event << "Last map:       #{last.date.strftime(DATE_FORMAT_OUTTE)} (#{last.id})"
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
  # Parse message parameters
  msg       = event.content
  player    = parse_player(msg, nil, true, true, false)
  author    = parse_author(msg, false)
  author_id = !author.nil? ? author.id : nil
  full      = parse_global(msg)
  mode      = parse_mode(msg, false, true)

  if full && player.nil? && author.nil?
    event.send_message("The global userlevel highscoring summary is disabled for now until it's optimized, you can still do the regular summary, or the global summary for a specific player or author.")
    return
  end

  # Fetch userlevels
  maps = full ? Userlevel.global : Userlevel.newest
  maps = maps.where(mode: mode.to_sym) if !mode.nil?
  maps = maps.where(author_id: author_id) if !author_id.nil?
  count = maps.count

  # Fetch scores
  scores = (player.nil? ? UserlevelScore : player).retrieve_scores(full, mode, author_id)
  count_a = scores.distinct.count(:userlevel_id)
  count_s = scores.count

  # Perform summary
  event << "#{format_global(full).capitalize} userlevel highscoring summary #{format_author(author)} #{"for #{player.name}" if !player.nil?}:".squish + "```"
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
    maxes     = Userlevel.ties(nil, true,  full, true, nil, author_id)
    maxables  = Userlevel.ties(nil, false, full, true, nil, author_id)
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

def send_userlevel_time(event)
  next_level = ($status_update + STATUS_UPDATE_FREQUENCY) - Time.now.to_i
  next_level_minutes = (next_level / 60).to_i
  next_level_seconds = next_level - (next_level / 60).to_i * 60

  event << "I'll update the userlevel database in #{next_level_minutes} minutes and #{next_level_seconds} seconds."
end

def send_userlevel_scores_time(event)
  next_level = GlobalProperty.get_next_update('userlevel_score') - Time.now
  next_level_hours = (next_level / (60 * 60)).to_i
  next_level_minutes = (next_level / 60).to_i - (next_level / (60 * 60)).to_i * 60

  event << "I'll update the *newest* userlevel scores in #{next_level_hours} hours and #{next_level_minutes} minutes."
end

def send_userlevel_times(event)
  send_userlevel_time(event)
  send_userlevel_scores_time(event)
end

# Exports userlevel database (bar level data) to CSV, for testing purposes.
def csv(event)
  assert_permissions(event)
  s = "id,author_id,author,title,favs,date,mode\n"
  s << Userlevel.all.map{ |m|
    "#{m.id},#{m.author_id},#{m.author.name},#{m.title},#{m.favs},#{m.date.strftime(DATE_FORMAT_OUTTE)},#{m.mode}"
  }.join("\n")
  File.write("userlevels.csv", s)
  event << "CSV exported."
end

def respond_userlevels(event)
  msg = event.content
  msg.sub!(/\A<@!?[0-9]*> */, '') # strip off the @inne++ mention, if present

  # methods that don't require special browsing terms
  if !(msg =~ /"/i)
    send_userlevel_spreads(event)     if msg =~ /spread/i
  end

  # exclusively global methods
  if !msg[NAME_PATTERN, 2]
    send_userlevel_rankings(event)   if msg =~ /\brank/i
  end

  send_userlevel_times(event)       if msg =~ /\bwhen\b/i
  send_userlevel_browse(event)      if msg =~ /\bbrowse\b/i || msg =~ /\bsearch\b/i
  send_userlevel_download(event)    if msg =~ /\bdownload\b/i
  send_userlevel_screenshot(event)  if msg =~ /\bscreenshots*\b/i
  send_userlevel_scores(event)      if msg =~ /scores\b/i # matches 'highscores'
  send_userlevel_count(event)       if msg =~ /how many/i
  send_userlevel_points(event)      if msg =~ /point/i && msg !~ /rank/i && msg !~ /average/i
  send_userlevel_avg_points(event)  if msg =~ /average/i && msg =~ /point/i && msg !~ /rank/i
  send_userlevel_avg_rank(event)    if msg =~ /average/i && msg =~ /rank/i && !!msg[NAME_PATTERN, 2]
  send_userlevel_avg_lead(event)    if msg =~ /average/i && msg =~ /lead/i && msg !~ /rank/i
  send_userlevel_total_score(event) if msg =~ /total score/i && msg !~ /rank/i
  send_userlevel_list(event)        if msg =~ /\blist\b/i
  send_userlevel_stats(event)       if msg =~ /stat/i
  send_userlevel_maxed(event)       if msg =~ /maxed/i
  send_userlevel_maxable(event)     if msg =~ /maxable/i
  send_random_userlevel(event)      if msg =~ /random/i
  send_userlevel_summary(event)     if msg =~ /summary/i
  #csv(event) if msg =~ /csv/i
end
