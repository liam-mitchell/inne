# TODO: This module should contain the functionality common to all maps:
#       Include it in Userlevels
module Map
  # pref - Drawing preference (for overlaps): lower = more to the front
  # att  - Number of object attributes in the old format
  # old  - ID in the old format, '-1' if it didn't exist
  # pal  - Index at which the colors of the object start in the palette image
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

  # Parse a level in Metanet format
  # This format is only used internally by the game for the campaign levels,
  # and differs from the standard userlevel format
  def self.parse_metanet_map(data, index = nil, file = nil, pack = nil)
    name =  ''
    name += " #{index}"       if !index.nil?
    name += " from '#{file}'" if !file.nil?
    name += " for '#{pack}'"  if !pack.nil?
    error = "Failed to parse Metanet formatted map#{name}"
    warning = "Abnormality found parsing Metanet formatted map#{name}"
    # Ensure format is "$map_name#map_data#", with map data being hex chars
    if data !~ /^\$(.*)\#(\h+)\#$/
      err("#{error}: Incorrect overall format.")
      return
    end
    title, map_data = $1, $2
    size = map_data.length

    # Map data is dumped binary, so length must be even, and long enough to hold
    # header and tile data
    if size % 2 == 1 || size / 2 < 4 + 23 * 42 + 2 * 26 + 4
      err("#{error}: Incorrect map data length (odd length, or too short).")
      return
    end

    # Map header missing
    if !map_data[0...8] == '00000000'
      err("#{error}: Header missing.")
      return
    end
    
    # Parse tiles. Warning if invalid ones are found
    tiles = [map_data[8...1940]].pack('h*').bytes
    invalid_count = tiles.count{ |t| t > 33 }
    if invalid_count > 0
      warn("#{warning}: #{invalid_count} invalid tiles.")
    end

    # Parse objects
    offset = 1940
    objects = []
    OBJECTS.reject{ |id, o| o[:old] == -1 }.sort_by{ |id, o| o[:old] }.each{ |id, type|
      # Parse object count
      if size < offset + 4
        err("#{error}: Object count for ID #{id} not found.")
        return
      end
      count = map_data[offset...offset + 4].scan(/../m).map(&:reverse).join.to_i(16)

      # Parse entities of this type
      if size < offset + 4 + 2 * count * type[:att]
        err("#{error}: Object data incomplete for ID #{id}.")
        return
      end
      map_data[offset + 4...offset + 4 + 2 * count * type[:att]].scan(/.{#{2 * type[:att]}}/m).each{ |o|
        atts = [o].pack('h*').bytes
        if ![3, 6, 8].include?(id)
          objects << [id] + atts.ljust(4, 0)
        else # Doors need special handling
          objects << [id] + atts[0..-3].ljust(4, 0) # Door
          objects << [id + 1] + atts[-2..-1].ljust(4, 0) # Door switch
        end
      }
      offset += 4 + 2 * count * type[:att]
    }
    # Sort objects by ID, but:
    #   1) In a stable way, i.e., maintaining the order of tied elements
    #   2) The pairs 6/7 and 8/9 are not sorted, but maintained staggered
    # Both are important to respect N++'s data format
    objects = objects.stable_sort_by{ |o| o[0] == 7 ? 6 : o[0] == 9 ? 8 : o[0] }

    # Warnings if footer is incorrect
    if size != offset + 8
      warn("#{warning}: Incorrect footer length.")
    elsif map_data[offset..-1] != '00000000'
      warn("#{warning}: Incorrect footer format.")
    end

    # Return map elements
    { title: title, tiles: tiles, objects: objects }
  end

  # Parse a text file containing maps in Metanet format, one per line
  # This is the format used by the game to store the main campaign of levels
  def self.parse_metanet_file(file, limit, pack)
    fn = File.basename(file)
    if !File.file?(file)
      err("File '#{fn}' not found parsing Metanet file")
      return
    end

    maps = File.binread(file).split("\n").take(limit)
    count = maps.count
    maps = maps.each_with_index.map{ |m, i|
      dbg("Parsing map #{"%-3d" % (i + 1)} / #{count} from '#{fn}' for '#{pack}'...", newline: false)
      parse_metanet_map(m, i, fn, pack)
    }
    Log.clear
    maps
  rescue => e
    err("Error parsing Metanet map file '#{fn}' for '#{pack}': #{e}")
    nil
  end

  def tiles
    Map.decode_tiles(data.tile_data)
  end

  def objects
    Map.decode_objects(data.object_data)
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

class Mappack < ActiveRecord::Base
  alias_attribute :levels, :mappack_levels
  alias_attribute :episodes, :mappack_episodes
  alias_attribute :stories, :mappack_stories
  has_many :mappack_levels
  has_many :mappack_episodes
  has_many :mappack_stories
  enum tab: TABS_NEW.map{ |k, v| [k, v[:mode] * 7 + v[:tab]] }.to_h

  # TODO: Add botmaster command to execute this function
  # TODO: Add botmaster command to add remaining details to a mappack (title,
  #       authors, etc)
  # Parse all mappacks in the mappack directory into the database
  # Only reads the newly added mappacks, unless 'update' is true
  def self.seed(update = false)
    if !Dir.exist?(DIR_MAPPACKS)
      err("Mappacks directory not found, not seeding")
      return
    end

    Dir.entries(DIR_MAPPACKS).select{ |d| !!d[/\d+_.+/] }.sort.each{ |d|
      id, code = d.split('_')
      mappack = Mappack.find_by(code: code)
      if mappack.nil?
        Mappack.create(id: id, code: code).read
      elsif update
        mappack.read
      end
    }
  rescue
    err("Error seeding mappacks to database")
  end

  # Parses map files corresponding to this mappack, and updates the database
  def read
    # Check for mappack directory
    log("Parsing mappack '#{code}'...")
    dir = File.join(DIR_MAPPACKS, "#{id}_#{code}")
    if !Dir.exist?(dir)
      err("Directory for mappack '#{code}' not found, not reading")
      return
    end

    # Fetch mappack files
    files = Dir.entries(dir).select{ |f|
      path = File.join(dir, f)
      File.file?(path) && File.extname(path) == ".txt"
    }.sort
    warn("No appropriate files found in directory for mappack '#{code}'") if files.count == 0

    # Delete old database records
    MappackLevel.where(mappack_id: id).delete_all
    MappackEpisode.where(mappack_id: id).delete_all
    MappackStory.where(mappack_id: id).delete_all

    # Parse mappack files
    file_errors = 0
    map_errors = 0
    files.each{ |f|
      # Find corresponding tab
      tab_code = f[0..-5]
      tab = TABS_NEW.find{ |tab, att| att[:files].key?(tab_code) }
      if tab.nil?
        warn("Unrecognized file '#{tab_code}' parsing mappack '#{code}'")
        next
      end

      # Parse file
      maps = Map.parse_metanet_file(File.join(dir, f), tab[1][:files][tab_code], code)
      if maps.nil?
        file_errors += 1
        next
      end

      # Precompute some indices for the database
      index          = tab[1][:files].keys.index(tab_code)
      mappack_offset = TYPES[0][:slots] * id
      tab_offset     = tab[1][:start]
      file_offset    = tab[1][:files].values.take(index).sum

      # Create new database records
      count = maps.count
      maps.each_with_index{ |map, map_offset|
        dbg("Creating record #{"%-3d" % (map_offset + 1)} / #{count} from '#{f}' for '#{code}'...", newline: false)
        if map.nil?
          map_errors += 1
          next
        end
        tab_id   = file_offset    + map_offset # ID of level within tab
        inner_id = tab_offset     + tab_id     # ID of level within mappack
        level_id = mappack_offset + inner_id   # ID of level in database

        # Create mappack level and data
        MappackLevel.find_or_create_by(id: level_id).update(
          inner_id:   inner_id,
          mappack_id: id,
          mode:       tab[1][:mode],
          tab:        tab[0],
          episode_id: level_id / 5,
          name:       code.upcase + '-' + compute_name(inner_id, 0),
          longname:   map[:title].strip,
        )
        MappackData.find_or_create_by(id: level_id).update(
          tile_data:   Map.encode_tiles(map[:tiles]),
          object_data: Map.encode_objects(map[:objects])
        )

        # Create corresponding mappack episode, except for secret tabs.
        next if tab[1][:secret]
        story = tab[1][:mode] == 0 && (!tab[1][:x] || map_offset < 5 * tab[1][:files][tab_code] / 6)
        MappackEpisode.find_or_create_by(id: level_id / 5).update(
          id:         level_id / 5,
          inner_id:   inner_id / 5,
          mappack_id: id,
          mode:       tab[1][:mode],
          tab:        tab[0],
          story_id:   story ? level_id / 25 : nil,
          name:       code.upcase + '-' + compute_name(inner_id / 5, 1)
        )

        # Create corresponding mappack story, only for non-X-Row Solo.
        next if !story
        MappackStory.find_or_create_by(id: level_id / 25).update(
          id:         level_id / 25,
          inner_id:   inner_id / 25,
          mappack_id: id,
          mode:       tab[1][:mode],
          tab:        tab[0],
          name:       code.upcase + '-' + compute_name(inner_id / 25, 2)
        )
      }
      Log.clear

      # Log results
      count = maps.count(nil)
      map_errors += count
      if count == 0
        dbg("Parsed file '#{tab_code}' for '#{code}' without errors")
      else
        warn("Parsed file '#{tab_code}' for '#{code}' with #{count} errors")
      end
    }

    if file_errors + map_errors == 0
      succ("Successfully parsed mappack '#{code}'")
    else
      warn("Parsed mappack '#{code}' with #{file_errors} file errors and #{map_errors} map errors")
    end
  rescue
    err("Error reading mappack '#{code}'")
  end
end

class MappackData < ActiveRecord::Base

end

class MappackLevel < ActiveRecord::Base
  include Map
  alias_attribute :scores, :mappack_scores
  alias_attribute :archives, :mappack_archives
  alias_attribute :episode, :mappack_episode
  has_many :mappack_scores, ->{ order(:rank) }, as: :highscoreable
  has_many :mappack_archives, as: :highscoreable
  belongs_to :mappack
  belongs_to :mappack_episode, foreign_key: :episode_id
  enum tab: TABS_NEW.map{ |k, v| [k, v[:mode] * 7 + v[:tab]] }.to_h

  def data
    MappackData.find(self.id)
  end
end

class MappackEpisode < ActiveRecord::Base
  alias_attribute :levels, :mappack_levels
  alias_attribute :scores, :mappack_scores
  alias_attribute :archives, :mappack_archives
  alias_attribute :story, :mappack_story
  has_many :mappack_levels, foreign_key: :episode_id
  has_many :mappack_scores, ->{ order(:rank) }, as: :highscoreable
  has_many :mappack_archives, as: :highscoreable
  belongs_to :mappack
  belongs_to :mappack_story, foreign_key: :story_id
  enum tab: TABS_NEW.map{ |k, v| [k, v[:mode] * 7 + v[:tab]] }.to_h
end

class MappackStory < ActiveRecord::Base
  alias_attribute :episodes, :mappack_episodes
  alias_attribute :scores, :mappack_scores
  alias_attribute :archives, :mappack_archives
  has_many :mappack_episodes, foreign_key: :story_id
  has_many :mappack_scores, ->{ order(:rank) }, as: :highscoreable
  has_many :mappack_archives, as: :highscoreable
  belongs_to :mappack
  enum tab: TABS_NEW.map{ |k, v| [k, v[:mode] * 7 + v[:tab]] }.to_h
end

class MappackScore < ActiveRecord::Base
  alias_attribute :scores, :mappack_scores
  alias_attribute :level, :mappack_level
  alias_attribute :episode, :mappack_episode
  alias_attribute :story, :mappack_story
  alias_attribute :archive, :mappack_archive
  belongs_to :player
  belongs_to :highscoreable, polymorphic: true
  belongs_to :mappack_archive, foreign_key: :archive_id
  #belongs_to :mappack_level, -> { where(scores: {highscoreable_type: 'Level'}) }, foreign_key: :highscoreable_id
  #belongs_to :mappack_episode, -> { where(scores: {highscoreable_type: 'Episode'}) }, foreign_key: :highscoreable_id
  #belongs_to :mappack_story, -> { where(scores: {highscoreable_type: 'Story'}) }, foreign_key: :highscoreable_id
  enum tab: TABS_NEW.map{ |k, v| [k, v[:mode] * 7 + v[:tab]] }.to_h

  # TODO: Implement for Episodes and Stories
  # TODO: Add integrity checks
  def self.add(code, submission)
    # Craft response
    res = {
      'better'    => 0,
      'score'     => submission['score'].to_i,
      'rank'      => -1,
      'replay_id' => -1,
      'user_id'   => submission['user_id'].to_i,
      'qt'        => submission['qt'].to_i,
      'level_id'  => submission['level_id'].to_i
    }

    # Find mappack
    mappack = Mappack.find_by(code: code)
    if mappack.nil?
      warn("Mappack '#{code}' not found")
      return res.to_json
    end

    # Find highscoreable
    sid = submission['level_id'].to_i
    level = MappackLevel.find_by(mappack: mappack, inner_id: sid)
    if level.nil?
      warn("Level ID:#{sid} for mappack '#{code}' not found")
      return res.to_json
    end

    # Find player
    uid = submission['user_id'].to_i
    player = Player.find_or_create_by(metanet_id: uid)

    # TODO: Fill rank and tied_rank
    # TODO: Create archive if score is higher, set previous one to expired
    # TODO: Create demo is score is higher

    # Update or create score
    s = (60.0 * submission['score'].to_i / 1000.0).round
    score = MappackScore.find_or_create_by(highscoreable: level, player: player)
    if score.score.nil? || score.score < s
      score.update(
        tab:        level.tab,
        mappack_id: mappack.id,
        score:      s
      )
      res['better'] = 1 # Did improve
    else
      res['better'] = 0 # Did not improve
    end
    res['replay_id'] = score.id # Perhaps choose the archive ID, which will always change if improved

    return res.to_json

    # TODO: Optionally, cut boards to 20 scores?
  rescue => e
    err("Failed to add score by ID:#{res['user_id']} in mappack '#{code}': #{e}")
    res.to_json
  end

end

class MappackArchive < ActiveRecord::Base
  belongs_to :player
  belongs_to :highscoreable, polymorphic: true
  enum tab: TABS_NEW.map{ |k, v| [k, v[:mode] * 7 + v[:tab]] }.to_h
end

class MappackDemo < ActiveRecord::Base

end

def respond_mappacks(event)
  msg = remove_mentions(event.content)

end