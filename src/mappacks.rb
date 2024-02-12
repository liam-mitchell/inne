# This file contains the generic Map module, that encapsulates a lot of the
# properties of an N++ map (map data format, screenshot generation, etc).
#
# Then, it includes all the classes related to mappacks (levels, episodes, stories,
# demos, etc), as well as the functions that handle the CLE server (Custom
# Leaderboard Engine).

#require 'chunky_png'
require 'oily_png'    # C wrapper for ChunkyPNG
require 'gifenc'      # Own gem to encode and decode GIFs
require 'digest'
require 'matplotlib/pyplot'
require 'zlib'

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
  # Objects that do not admit rotations
  FIXED_OBJECTS = [0, 1, 2, 3, 4, 7, 9, 16, 17, 18, 19, 21, 22, 24, 25, 28]
  # Objects that admit diagonal rotations
  SPECIAL_OBJECTS = [10, 11, 23]
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
  # Challenge: Figure out what the following constant encodes ;)
  BORDERS = "100FF87E1781E0FC3F03C0FC3F03C0FC3F03C078370388FC7F87C0EC1E01C1FE3F13E"
  DEFAULT_PALETTE = "vasquez"
  PALETTE = ChunkyPNG::Image.from_file(PATH_PALETTES)
  ROWS    = 23
  COLUMNS = 42
  UNITS   = 24               # Game units per tile
  DIM     = 44               # Pixels per tile at 1080p
  PPC     = 11               # Pixels per coordinate (1/4th tile)
  PPU     = DIM.to_f / UNITS # Pixels per unit
  WIDTH   = DIM * (COLUMNS + 2)
  HEIGHT  = DIM * (ROWS + 2)

  # TODO: Perhaps store object data without transposing, hence being able to skip
  #       the decoding when dumping
  # TODO: Or better yet, store the entire map data in a single field, Zlibbed, for
  #       instantaneous dumps
  def self.encode_tiles(data)
    Zlib::Deflate.deflate(data.map{ |a| a.pack('C*') }.join, 9)
  end

  def self.encode_objects(data)
    Zlib::Deflate.deflate(data.transpose.map{ |a| a.pack('C*') }.join, 9)
  end

  def self.decode_tiles(data)
    Zlib::Inflate.inflate(data).bytes.each_slice(42).to_a
  end

  def self.decode_objects(data)
    dec = Zlib::Inflate.inflate(data)
    dec.bytes.each_slice((dec.size / 5).round).to_a.transpose
  end

  # Parse a level in Metanet format
  # This format is only used internally by the game for the campaign levels,
  # and differs from the standard userlevel format
  def self.parse_metanet_map(data, index = nil, file = nil, pack = nil)
    name =  ''
    name += " #{index}"     if !index.nil?
    name += " from #{file}" if !file.nil?
    name += " for #{pack}"  if !pack.nil?
    error = "Failed to parse map#{name}"
    warning = "Abnormality found parsing map#{name}"

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
    tiles = tiles.each_slice(42).to_a

    # Parse objects
    offset = 1940
    objects = []
    gold = 0
    OBJECTS.reject{ |id, o| o[:old] == -1 }.sort_by{ |id, o| o[:old] }.each{ |id, type|
      # Parse object count
      if size < offset + 4
        err("#{error}: Object count for ID #{id} not found.")
        return
      end
      count = map_data[offset...offset + 4].scan(/../m).map(&:reverse).join.to_i(16)
      gold = count if id == 2

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
    { title: title, tiles: tiles, objects: objects, gold: gold }
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
      dbg("Parsing map #{"%-3d" % (i + 1)} / #{count} from #{fn} for #{pack}...", progress: true)
      parse_metanet_map(m.strip, i, fn, pack)
    }
    Log.clear
    maps
  rescue => e
    lex(e, "Error parsing Metanet map file #{fn} for #{pack}")
    nil
  end

  def self.object_counts(objects)
    object_counts = [0] * 40
    objects.each{ |o| object_counts[o[0]] += 1 if o[0] < 40 }
    object_counts
  end

  def print_scores
    update_scores if !OFFLINE_STRICT
    if scores.count == 0
      board = "This userlevel has no highscores!"
    else
      board = scores.map{ |s| { score: s.score / 60.0, player: s.player.name } }
      pad = board.map{ |s| s[:score] }.max.to_i.to_s.length + 4
      board.each_with_index.map{ |s, i|
        "#{Highscoreable.format_rank(i)}: #{format_string(s[:player])} - #{"%#{pad}.3f" % [s[:score]]}"
      }.join("\n")
    end
  end

  # Return tiles as a matrix of integer
  def tiles(version: nil)
    Map.decode_tiles(tile_data(version: version))
  end

  # Return objects as an array of 5-tuples of ints
  def objects(version: nil)
    Map.decode_objects(object_data(version: version))
  end

  # Return object counts
  def object_counts(version: nil)
    Map.object_counts(objects(version: version))
  end

  # Shortcuts for some object counts
  def gold(version: nil)
    object_counts(version: version)[2]
  end

  def mines(version: nil)
    object_counts(version: version)[1]
  end

  # This is used for computing the hash of a level. It's required due to a
  # misimplementation in N++, which instead of just hashing the map data,
  # overflows and copies object data from the next levels before doing so.
  #   Returns false if we ran out of objects, or true if we completed the data
  # successfully. Userlevels aren't completed (their hashes aren't checked
  # by the server anyways).
  #  Params:
  # - data: Current object data
  # - n:    Count of remaining objects needed to complete data
  def complete_object_data(data, n)
    return true if n == 0 || self.is_a?(Userlevel)
    successor = next_h(tab: false)
    return false if successor == self
    objs = successor.objects.take(n).map{ |o| o.pack('C5') }
    count = objs.count
    data << objs.join
    return true if count == n
    successor.complete_object_data(data, n - count)
  end

  # Generate a file with the usual userlevel format
  #   - query:   The format for userlevel query files is used (shorter header)
  #   - hash:    Recursively fetches object data from next level to compute hash later
  #   - version: Version of the map (for mappacks we may hold multiple edits)
  def dump_level(query: false, hash: false, version: nil)
    objs = self.objects(version: version)
    # HEADER
    header = ""
    if !query
      header << _pack(0, 4)                    # Magic number
      header << _pack(1230 + 5 * objs.size, 4) # Filesize
    end
    mode = self.is_a?(MappackLevel) ? self.mode : Userlevel.modes[self.mode]
    author_id = query ? self.author_id : -1
    title = self.is_a?(MappackLevel) ? self.longname : self.title
    title = to_ascii(title.to_s)[0...127].ljust(128, "\x00")
    header << _pack(-1, 'l<')        # Level ID (unset)
    header << _pack(mode, 4)         # Game mode
    header << _pack(37, 4)           # QT (unset, max is 36)
    header << _pack(author_id, 'l<') # Author ID
    header << _pack(0, 4)            # Fav count (unset)
    header << _pack(0, 10)           # Date SystemTime (unset)
    header << title                  # Title
    header << _pack(0, 16)           # Author name (unset)
    header << _pack(0, 2)            # Padding

    # MAP DATA
    tile_data = Zlib::Inflate.inflate(tile_data(version: version))
    object_counts = Map.object_counts(objs)
    object_counts[7] = 0 unless hash
    object_counts[9] = 0 unless hash
    object_data = objs.map{ |o| o.pack('C5') }.join
    return nil if hash && !complete_object_data(object_data, object_counts[6] + object_counts[8])
    object_counts = object_counts.pack('S<*')

    # TODO: Perhaps optimize the commented code below, in case it's useful in the future

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
    (header + tile_data + object_counts + object_data).force_encoding("ascii-8bit")
  end

  # Computes the level's hash, which the game uses for integrity verifications
  #   c   - Use the C SHA1 implementation (vs. the default Ruby one)
  #   v   - Map version to hash
  #   pre - Serve precomputed hash stored in BadHash table
  def hash(c: false, v: nil, pre: false)
    stored = l.hashes.where("version <= #{v}").order(:version).last rescue nil
    return stored if pre && stored
    map_data = dump_level(hash: true, version: v)
    return nil if map_data.nil?
    sha1(PWD + map_data[0xB8..-1], c: c)
  end

  # <-------------------------------------------------------------------------->
  #                           SCREENSHOT GENERATOR
  # <-------------------------------------------------------------------------->

  # Change color 'before' to color 'after' in 'image'.
  # The normal version uses tolerance to change close enough colors, alpha blending...
  # The fast version doesn't do any of this, but is 10x faster
  def self.mask(image, before, after, bg: ChunkyPNG::Color::WHITE, tolerance: 0.5, fast: false)
    if fast
      image.pixels.map!{ |p| p == before ? after : 0 }
      image
    else
      new_image = ChunkyPNG::Image.new(image.width, image.height, ChunkyPNG::Color::TRANSPARENT)
      image.width.times{ |x|
        image.height.times{ |y|
          score = ChunkyPNG::Color.euclidean_distance_rgba(image[x,y], before).to_f / ChunkyPNG::Color::MAX_EUCLIDEAN_DISTANCE_RGBA
          if score < tolerance then new_image[x,y] = ChunkyPNG::Color.compose(after, bg) end
        }
      }
      new_image
    end
  end

  # Generate the image of an object in the specified palette, by painting and combining each layer.
  # Note: "special" indicates that we take the special version of the layers. In practice,
  # this is used because we can't rotate images 45 degrees with this library, so we have a
  # different image for that, which we call special.
  def self.generate_object(object_id, palette_id, object = true, special = false)
    # Select necessary layers
    path = object ? PATH_OBJECTS : PATH_TILES
    parts = Dir.entries(path).select{ |file| file[0..1] == object_id.to_s(16).upcase.rjust(2, "0") }.sort
    parts_normal = parts.select{ |file| file[-6] == "-" }
    parts_special = parts.select{ |file| file[-6] == "s" }
    parts = (!special ? parts_normal : (parts_special.empty? ? parts_normal : parts_special))

    # Paint and combine the layers
    masks = parts.map{ |part| [part[-5], ChunkyPNG::Image.from_file(File.join(path, part))] }
    images = masks.map{ |mask| mask(mask[1], ChunkyPNG::Color::BLACK, PALETTE[(object ? OBJECTS[object_id][:pal] : 0) + mask[0].to_i, palette_id], fast: true) }
    dims = [ images.map{ |i| i.width }.max, images.map{ |i| i.height }.max ]
    output = ChunkyPNG::Image.new(*dims, ChunkyPNG::Color::TRANSPARENT)
    images.each{ |image| output.compose!(image, 0, 0) }
    output
  end

  # Generate a PNG screenshot of a level in the chosen palette.
  # Optionally, plot animated routes and export to GIF.
  # [Depends on ChunkyPNG, a pure Ruby library]
  #
  # Note: This function is forked to a different process, because ChunkyPNG has
  #       memory leaks we cannot handle.
  def self.screenshot(
      theme =  DEFAULT_PALETTE, # Palette to generate screenshot in
      file:    false,           # Whether to export to a file or return the raw data
      blank:   false,           # Only draw background
      ppc:     0,               # Points per coordinate (essentially the scale) (0 = use default)
      h:       nil,             # Highscoreable to screenshot
      anim:    false,           # Whether to animate plotted coords or not
      use_gif: true,            # Use GIF or MP4 for animated traces
      coords:  [],              # Coordinates of routes to trace
      spoiler: false,           # Whether the screenshot should be spoilered in Discord
      v:       nil              # Version of the map data to use (nil = latest)
    )

    bench(:start) if BENCHMARK

    res = _fork do
      # Parse palette and colors
      bench(:start) if BENCH_IMAGES
      return nil if h.nil?
      themes = THEMES.map(&:downcase)
      theme = theme.downcase
      if !themes.include?(theme) then theme = DEFAULT_PALETTE end
      palette_idx = themes.index(theme)
      bg_color = PALETTE[2, palette_idx]
      fg_color = PALETTE[0, palette_idx]
      anim = false if !FEATURE_ANIMATE

      # Prepare map data and other graphic params
      if h.is_a?(Levelish)
        maps = [h]
        ppc = ppc == 0 ? PPC : ppc
        cols = 1
        rows = 1
      elsif h.is_a?(Episodish)
        maps = h.levels
        ppc = ppc == 0 ? 3 : ppc
        cols = 5
        rows = 1
      else
        maps = h.episodes.map{ |e| e.levels }.flatten
        ppc = ppc == 0 ? 2 : ppc
        cols = 5
        rows = 5
      end

      # Compute scale params
      dim = 4 * ppc          # Dimension of a tile, in pixels
      ppu = dim.to_f / UNITS # Pixels per in-game unit
      scale = ppc.to_f / PPC # Scale of screenshot

      # Initialize image
      width = dim * (COLUMNS + 2)
      height = dim * (ROWS + 2)
      frame = !h.is_a?(Levelish)
      image = ChunkyPNG::Image.new(
        cols * width  + (cols - 1) * dim + (frame ? 2 : 0) * dim,
        rows * height + (rows - 1) * dim + (frame ? 2 : 0) * dim,
        bg_color
      )
      next image.to_blob(:fast_rgba) if blank
      bench(:step, 'Setup     ') if BENCH_IMAGES

      # Parse map
      tiles = maps.map{ |m| m.tiles(version: v).map(&:dup) }
      objects = maps.map{ |m|
        m.objects(version: v)
         .reject{ |o| o[0] > 28 || o[0] == 8 } # Remove glitch objs and trap doors
         .sort_by{ |o| -OBJECTS[o[0]][:pref] } # Sort objs by overlap preference
      }
      objects.each{ |m|
        m.each{ |o|
          o[3] = 0 if o[3] > 7 || FIXED_OBJECTS.include?(o[0]) # Remove glitched orientations
        }
      }
      bench(:step, 'Parse     ') if BENCH_IMAGES

      # Initialize tile images
      tile = {}
      tiles.each{ |m|
        m.each{ |row|
          row.each{ |t|
            # Skip if this tile is already initialized
            next if tile.key?(t) || t <= 1 || t >= 34

            # Initialize base tile image
            o = (t - 2) % 4                # Orientation
            base = t - o                   # Base shape
            if !tile.key?(base)
              tile[base] = generate_object(base, palette_idx, false)
              tile[base].resample_bilinear!(
                (scale * tile[base].width).round,
                (scale * tile[base].height).round,
              ) if ppc != PPC
            end
            next if base == t

            # Initialize rotated / flipped copies
            if t >= 2 && t <= 17           # Half tiles and curved slopes
              case o
              when 1
                tile[t] = tile[base].rotate_right
              when 2
                tile[t] = tile[base].rotate_180
              when 3
                tile[t] = tile[base].rotate_left
              end
            elsif t >= 18 && t <= 33       # Small and big straight slopes
              case o
              when 1
                tile[t] = tile[base].flip_vertically
              when 2
                tile[t] = tile[base].flip_horizontally.flip_vertically
              when 3
                tile[t] = tile[base].flip_horizontally
              end
            end
          }
        }
      }
      bench(:step, 'Init tiles') if BENCH_IMAGES

      # Initialize object images
      object = 30.times.map{ |i| [i, {}] }.to_h
      objects.each{ |m|
        m.each{ |o|
          # Skip if this object is already initialized
          next if object.key?(o[0]) && object[o[0]].key?(o[3])

          # Initialize base object image
          s = o[3] % 2 == 1 && SPECIAL_OBJECTS.include?(o[0]) # Special variant of sprite (diagonal)
          base = s ? 1 : 0
          if !object[o[0]].key?(base)
            object[o[0]][base] = generate_object(o[0], palette_idx, true, s)
            object[o[0]][base].resample_bilinear!(
              (scale * object[o[0]][base].width).round,
              (scale * object[o[0]][base].height).round,
            ) if ppc != PPC
          end
          next if o[3] <= 1

          # Initialize rotated copies
          case o[3] / 2
          when 1
            object[o[0]][o[3]] = object[o[0]][base].rotate_right
          when 2
            object[o[0]][o[3]] = object[o[0]][base].rotate_180
          when 3
            object[o[0]][o[3]] = object[o[0]][base].rotate_left
          end
        }
      }
      bench(:step, 'Init objs ') if BENCH_IMAGES

      # Parse tile borders
      border = BORDERS.to_i(16).to_s(2)[1..-1].chars.map(&:to_i).each_slice(8).to_a

      # Draw objects
      off_x = frame ? dim : 0
      off_y = frame ? dim : 0
      objects.each_with_index do |m, i|
        # Compose images
        m.each do |o|
          next if !object.key?(o[0])
          r = object[o[0]].key?(o[3]) ? o[3] : object[o[0]].keys.first
          next if r.nil?
          obj = object[o[0]][r]
          image.compose!(obj, off_x + ppc * o[1] - obj.width / 2, off_y + ppc * o[2] - obj.height / 2) rescue nil
        end

        # Adjust offsets
        off_x += width + dim
        if i % 5 == 4
          off_x = frame ? dim : 0
          off_y += height + dim
        end
      end
      bench(:step, 'Objects   ') if BENCH_IMAGES

      # Draw tiles
      off_x = frame ? dim : 0
      off_y = frame ? dim : 0
      tiles.each_with_index do |m, i|
        # Prepare tiles
        m.each{ |row| row.unshift(1).push(1) }                   # Add vertical frame
        m.unshift([1] * (COLUMNS + 2)).push([1] * (COLUMNS + 2)) # Add horizontal frame
        m.each{ |row| row.map!{ |t| t > 33 ? 0 : t } }           # Reject glitch tiles

        # Draw images
        m.each_with_index do |slice, row|
          slice.each_with_index do |t, column|
            # Empty and full tiles are handled separately
            next if t == 0
            if t == 1
              image.fast_rect(
                off_x + dim * column,
                off_y + dim * row,
                off_x + dim * column + dim - 1,
                off_y + dim * row + dim - 1,
                nil,
                fg_color
              )
              next
            end

            # Compose all other tiles
            next if !tile.key?(t)
            image.compose!(tile[t], off_x + dim * column, off_y + dim * row)
          end
        end

        # Adjust offsets
        off_x += width + dim
        if i % 5 == 4
          off_x = frame ? dim : 0
          off_y += height + dim
        end
      end
      bench(:step, 'Tiles     ') if BENCH_IMAGES

      # Draw tile borders
      bd_color = PALETTE[1, palette_idx]
      off_x = frame ? dim : 0
      off_y = frame ? dim : 0
      thin = ppc <= 6
      tiles.each_with_index do |m, i|
        #                  Frame surrounding entire level
        if frame
          image.fast_rect(
            off_x, off_y, off_x + width - 1, off_y + height - 1, bd_color, nil
          )
          image.fast_rect(
            off_x + 1, off_y + 1, off_x + width - 2, off_y + height - 2, bd_color, nil
          )
        end

        #                  Horizontal borders
        (0 .. ROWS).each do |row|
          (0 ... 2 * (COLUMNS + 2)).each do |col|
            tile_a = m[row][col / 2]
            tile_b = m[row + 1][col / 2]
            bool = col % 2 == 0 ? (border[tile_a][3] + border[tile_b][6]) % 2 : (border[tile_a][2] + border[tile_b][7]) % 2
            image.fast_rect(
              off_x + dim / 2 * col - (thin ? 0 : 1),
              off_y + dim * (row + 1) - (thin ? 0 : 1),
              off_x + dim / 2 * (col + 1) - (thin ? 1 : 0),
              off_y + dim * (row + 1),
              nil,
              bd_color
            ) if bool == 1
          end
        end

        #                  Vertical borders
        (0 ... 2 * (ROWS + 2)).each do |row|
          (0 .. COLUMNS).each do |col|
            tile_a = m[row / 2][col]
            tile_b = m[row / 2][col + 1]
            bool = row % 2 == 0 ? (border[tile_a][0] + border[tile_b][5]) % 2 : (border[tile_a][1] + border[tile_b][4]) % 2
            image.fast_rect(
              off_x + dim * (col + 1) - (thin ? 0 : 1),
              off_y + dim / 2 * row - (thin ? 0 : 1),
              off_x + dim * (col + 1),
              off_y + dim / 2 * (row + 1) - (thin ? 1 : 0),
              nil,
              bd_color
            ) if bool == 1
          end
        end

        # Adjust offsets
        off_x += width + dim
        if i % 5 == 4
          off_x = frame ? dim : 0
          off_y += height + dim
        end
      end
      bench(:step, 'Borders   ') if BENCH_IMAGES

      # Plot routes
      if !coords.empty? && h.is_a?(Levelish)
        # Prepare parameters
        coords = coords.take(MAX_TRACES).reverse
        n = [coords.size, MAX_TRACES].min
        ninja_colors = n.times.map{ |i| PALETTE[OBJECTS[0][:pal] + n - 1 - i, palette_idx] }

        # Scale coordinates
        coords.each{ |c_list|
          c_list.each{ |coord|
            coord.map!{ |c| (ppu * c).round }
          }
        }

        if use_gif
          # Build GIF palette. Since each palette only supports a max of 256 colors,
          # we sort the colors by frequency and take the top 256 ones (usually we
          # actually have way fewer).
          frequencies = Hash.new(0)
          image.pixels.each{ |color| frequencies[color] += 1 }
          colors = frequencies.sort_by{ |color, freq| -freq }
                              .take(256)
                              .map{ |c| c[0] >> 8 }
          palette = Gifenc::ColorTable.new(colors).compact
          ninja_colors.each{ |c| palette.add(c >> 8) }
          index = palette.colors.compact.each_with_index.to_h

          # Construct GIF and add background image
          bg = index[bg_color >> 8]
          gif = Gifenc::Gif.new(image.width, image.height, gct: palette, loops: -1)
          gif.images << Gifenc::Image.new(image.width, image.height, color: bg)
                                    .replace(image.pixels.map{ |c| index[c >> 8] })

          # Plot lines
          sizes = coords.map(&:size)
          frames = sizes.max
          step = 3
          (0 .. frames - 2).step(step) do |f|
            dbg("Generating frame #{'%4d' % [f + 1]} / #{frames - 1}", newline: false) if BENCH_IMAGES
            # Find bounding box
            endpoints = []
            coords.each_with_index{ |c_list, i|
              next if sizes[i] < f + step + 1
              endpoints << [c_list[f][0], c_list[f][1]]
              endpoints << [c_list[f + step][0], c_list[f + step][1]]
            }
            next if endpoints.empty?
            bbox = Gifenc::Image.bbox(endpoints, 1)

            # Add new frame
            gif.images << Gifenc::Image.new(
              bbox[2], bbox[3], bbox[0], bbox[1], color: bg, delay: 2, trans_color: bg
            )

            # Draw each line
            coords.each_with_index{ |c_list, i|
              next if sizes[i] < f + step + 1
              point_a = [c_list[f][0], c_list[f][1]]
              point_b = [c_list[f + step][0], c_list[f + step][1]]
              x0 = point_a[0] - bbox[0]
              y0 = point_a[1] - bbox[1]
              x1 = point_b[0] - bbox[0]
              y1 = point_b[1] - bbox[1]
              color = index[ninja_colors[i] >> 8]
              gif.images.last.line(p1: [x0, y0], p2: [x1, y1], color: color, weight: 2)
            }
          end
        else
          # Plot lines
          sizes = coords.map(&:size)
          frames = sizes.max
          for f in (0 .. frames - 2) do
            dbg("Generating frame #{'%4d' % [f + 1]} / #{frames - 1}", newline: false) if BENCH_IMAGES
            coords.each_with_index{ |c_list, i|
              image.line(
                c_list[f][0],
                c_list[f][1],
                c_list[f + 1][0],
                c_list[f + 1][1],
                ninja_colors[i],
                false,
                weight: 2,
                antialiasing: false
              ) if sizes[i] >= f + 2
            }
            image.save("frames/#{'%04d' % f}.png", :fast_rgb) if anim
          end
        end
        bench(:step, 'Routes    ') if BENCH_IMAGES
      end

      # rb_p(rb_str_new_cstr("Hello, world!"));
      # rb_p(rb_sprintf("x0 = %ld", x0));
      if anim
        if use_gif
          res = gif.write
        else
          `ffmpeg -framerate 60 -pattern_type glob -i 'frames/*.png' 'frames/anim.mp4' > /dev/null 2>&1`
          res = File.binread('frames/anim.mp4')
          FileUtils.rm(Dir.glob('frames/*'))
        end
      else
        res = image.to_blob(:fast_rgb)
      end
      bench(:step, 'Blobify   ') if BENCH_IMAGES

      res
    end

    bench(:step) if BENCHMARK

    return nil if !res
    ext = !anim ? 'png' : use_gif ? 'gif' : 'mp4'
    file ? tmp_file(res, "#{spoiler ? 'SPOILER_' : ''}#{h.name}.#{ext}", binary: true) : res
  rescue => e
    lex(e, "Failed to generate screenshot")
    nil
  end

  def screenshot(
      theme = DEFAULT_PALETTE,
      file:    false,
      blank:   false,
      anim:    false,
      use_gif: false,
      coords:  [],
      spoiler: false,
      v:       nil
    )
    Map.screenshot(
      theme,
      file:    file,
      blank:   blank,
      anim:    anim,
      use_gif: use_gif,
      coords:  coords,
      h:       self,
      ppc:     anim ? 5 : 0,
      spoiler: spoiler,
      v:       v
    )
  end

  # Plot routes and legend on top of an image (typically a screenshot)
  # [Depends on Matplotlib using Pycall, a Python wrapper]
  #
  # Note: This function is forked to a different process, because Matplotlib has
  #       memory leaks we cannot handle.
  def _trace(
      theme:   DEFAULT_PALETTE, # Palette to generate screenshot in
      bg:      nil,             # Background image (screenshot) file object
      animate: false,           # Animate trace instead of still image
      coords:  [],              # Array of coordinates to plot routes
      demos:   [],              # Array of demo inputs, to mark parts of the route
      texts:   [],              # Names for the legend
      markers: { jump: true, left: false, right: false} # Mark changes in replays
    )
    return if coords.empty?

    _fork do
      # Parse palette
      bench(:start) if BENCH_IMAGES
      themes = THEMES.map(&:downcase)
      theme = theme.to_s.downcase
      theme = DEFAULT_PALETTE.downcase if !themes.include?(theme)
      palette_idx = themes.index(theme)

      # Setup parameters and Matplotlib
      coords = coords.take(MAX_TRACES).reverse
      demos = demos.take(MAX_TRACES).reverse
      texts = texts.take(MAX_TRACES).reverse
      n = [coords.size, MAX_TRACES].min
      color_idx = OBJECTS[0][:pal]
      colors = n.times.map{ |i| ChunkyPNG::Color.to_hex(PALETTE[color_idx + n - 1 - i, palette_idx]) }
      Matplotlib.use('agg')
      mpl = Matplotlib::Pyplot
      mpl.ioff

      # Prepare custom font (Sys)
      font = "#{DIR_UTILS}/sys.ttf"
      fm = PyCall.import_module('matplotlib.font_manager')
      fm.fontManager.addfont(font)
      mpl.rcParams['font.family'] = 'sans-serif'
      mpl.rcParams['font.sans-serif'] = fm.FontProperties.new(fname: font).get_name
      bench(:step, 'Trace setup') if BENCH_IMAGES

      # Configure axis
      dx = (COLUMNS + 2) * UNITS
      dy = (ROWS + 2) * UNITS
      mpl.axis([0, dx, dy, 0])
      mpl.axis('off')
      ax = mpl.gca
      ax.set_aspect('equal', adjustable: 'box')

      # Load background image (screenshot)
      img = mpl.imread(bg)
      ax.imshow(img, extent: [0, dx, dy, 0])
      bench(:step, 'Trace image') if BENCH_IMAGES

      # Plot inputs
      n.times.each{ |i|
        break if markers.values.count(true) == 0  || demos[i].nil?
        demos[i].each_with_index{ |f, j|
          if markers[:jump] && f[0] == 1 && (j == 0 || demos[i][j - 1][0] == 0)
            mpl.plot(coords[i][j][0], coords[i][j][1], color: colors[i], marker: '.', markersize: 1)
          end
          if markers[:right] && f[1] == 1 && (j == 0 || demos[i][j - 1][1] == 0)
            mpl.plot(coords[i][j][0], coords[i][j][1], color: colors[i], marker: '>', markersize: 1)
          end
          if markers[:left] && f[2] == 1 && (j == 0 || demos[i][j - 1][2] == 0)
            mpl.plot(coords[i][j][0], coords[i][j][1], color: colors[i], marker: '<', markersize: 1)
          end
        }
      }
      bench(:step, 'Trace input') if BENCH_IMAGES

      # Plot legend
      n.times.each{ |i|
        break if texts[i].nil?
        name, score = texts[i].match(/(.*)-(.*)/).captures.map(&:strip)
        dx = UNITS * COLUMNS / 4.0
        ddx = UNITS / 2
        bx = UNITS / 4
        c = 8
        m = dx / 2.9
        dm = 4
        x, y = UNITS + dx * (n - i - 1), UNITS - 5
        vert_x = [x + bx, x + bx, x + bx + c, x + dx - m - dm, x + dx - m, x + dx - m + dm, x + dx - bx - c, x + dx - bx, x + dx - bx]
        vert_y = [2, UNITS - c - 2, UNITS - 2, UNITS - 2, UNITS - dm - 2, UNITS - 2, UNITS - 2, UNITS - c - 2, 2]
        color_bg = ChunkyPNG::Color.to_hex(PALETTE[2, palette_idx])
        color_bd = colors[i]
        mpl.fill(vert_x, vert_y, facecolor: color_bg, edgecolor: color_bd, linewidth: 0.5)
        mpl.text(x + ddx, y, name, ha: 'left', va: 'baseline', color: colors[i], size: 'x-small')
        mpl.text(x + dx - ddx, y, score, ha: 'right', va: 'baseline', color: colors[i], size: 'x-small')
      }
      bench(:step, 'Trace texts') if BENCH_IMAGES

      # Plot or animate traces
      # Note: I've deprecated the animation code because the performance was horrible.
      # Instead, for animations I render each frame in the screenshot function,
      # and then call ffmpeg to render an mp4.
      if false# animate
        anim = PyCall.import_module('matplotlib.animation')
        x = []
        y = []
        plt = mpl.plot(x, y, colors[0], linewidth: 0.5)
        an = anim.FuncAnimation.new(
          mpl.gcf,
          -> (f) {
            x << coords[0][f][0]
            y << coords[0][f][1]
            plt[0].set_data(x, y)
            plt
          },
          frames: 20,
          interval: 200
        )
        an.save(
          '/mnt/c/Users/Usuario2/Downloads/N/test.gif',
          writer: 'imagemagick',
          savefig_kwargs: { bbox_inches: 'tight', pad_inches: 0, dpi: 390 }
        )
      else
        coords.each_with_index{ |c, i|
          mpl.plot(c.map(&:first), c.map(&:last), colors[i], linewidth: 0.5)
        }
      end
      bench(:step, 'Trace plot ') if BENCH_IMAGES

      # Save result
      fn = tmp_filename("#{name}_aux.png")
      mpl.savefig(fn, bbox_inches: 'tight', pad_inches: 0, dpi: 390, pil_kwargs: { compress_level: 1 })
      image = File.binread(fn)
      bench(:step, 'Trace save ') if BENCH_IMAGES

      # Perform cleanup
      mpl.cla
      mpl.clf
      mpl.close('all')

      # Return
      image
    end
  end

  def trace(event, anim: false)
    t = Time.now
    msg = parse_message(event)
    tmp_msg = [nil]
    h = parse_palette(event)
    msg, palette, error = h[:msg], h[:palette], h[:error]
    level = self.is_a?(MappackHighscoreable) && mappack.id == 0 ? Level.find_by(id: id) : self
    perror("Error finding level object") if level.nil?
    mappack = level.is_a?(MappackHighscoreable)
    userlevel = level.is_a?(Userlevel)
    board = parse_board(msg, 'hs')
    perror("Non-highscore modes (e.g. speedrun) are only available for mappacks") if !mappack && board != 'hs'
    perror("Traces are only available for either highscore or speedrun mode") if !['hs', 'sr'].include?(board)
    leaderboard = level.leaderboard(board, pluck: false)
    ranks = parse_ranks(msg, leaderboard.size).take(MAX_TRACES)
    scores = ranks.map{ |r| leaderboard[r] }.compact
    perror("No scores found for this level") if scores.empty?
    blank = !!msg[/\bblank\b/i]
    markers = { jump: false, left: false, right: false } if !!msg[/\bplain\b/i]
    markers = { jump: true,  left: true,  right: true  } if !!msg[/\binputs\b/i]
    markers = { jump: true,  left: false, right: false } if markers.nil?
    use_gif = true

    # Export input files
    demos = []
    concurrent_edit(event, tmp_msg, "Downloading replays...") if userlevel
    File.binwrite('map_data', dump_level)
    scores.each_with_index.map{ |s, i|
      demo = userlevel ? Demo.encode(s.demo) : s.demo.demo
      demos << Demo.decode(demo)
      File.binwrite("inputs_#{i}", demo)
    }
    concurrent_edit(event, tmp_msg, 'Calculating routes...')
    shell("python3 #{PATH_NTRACE}", stream: true)

    # Read output files
    file = File.binread('output.txt') rescue nil
    perror("ntrace failed, please contact the botmaster for details.") if file.nil?
    valid = file.scan(/True|False/).map{ |b| b == 'True' }
    coords = file.split(/True|False/)[1..-1].map{ |d|
      d.strip.split("\n").map{ |c| c.split(' ').map(&:to_f) }
    }
    FileUtils.rm(['map_data', *Dir.glob('inputs_*'), 'output.txt'])

    # Draw
    names = scores.map{ |s| s.player.print_name }
    wrong_names = names.each_with_index.select{ |_, i| !valid[i] }.map(&:first)
    event << error.strip if !error.empty?
    event << "Replay #{format_board(board)} #{'trace'.pluralize(names.count)} for #{names.to_sentence} in #{userlevel ? "userlevel #{verbatim(level.name)}" : level.name} in palette #{verbatim(palette)}:"
    texts = level.format_scores(np: 11, mode: board, ranks: ranks, join: false, cools: false, stars: false)
    event << "(**Warning**: #{'Trace'.pluralize(wrong_names.count)} for #{wrong_names.to_sentence} #{wrong_names.count == 1 ? 'is' : 'are'} likely incorrect)." if valid.count(false) > 0
    concurrent_edit(event, tmp_msg, 'Generating screenshot...')
    if anim
      trace = screenshot(palette, coords: coords, blank: blank, anim: true, use_gif: use_gif)
      perror('Failed to generate screenshot') if trace.nil?
    else
      screenshot = screenshot(palette, file: true, blank: blank)
      perror('Failed to generate screenshot') if screenshot.nil?
      concurrent_edit(event, tmp_msg, 'Plotting routes...')
      trace = _trace(
        theme:   palette,
        bg:      screenshot,
        coords:  coords,
        demos:   demos,
        markers: markers,
        texts:   !blank ? texts : []
      )
      screenshot.close
      perror('Failed to trace replays') if trace.nil?
    end
    ext = anim ? (use_gif ? 'gif' : 'mp4') : 'png'
    send_file(event, trace, "#{name}_#{ranks.map(&:to_s).join('-')}_trace.#{ext}", true)
    tmp_msg.first.delete rescue nil
    log("FINAL: #{"%8.3f" % [1000 * (Time.now - t)]}") if BENCH_IMAGES
  rescue OutteError => e
    # TODO: See if we can refactor this to avoid having to reference OutteError
    # directly and making this handling more elegant
    !tmp_msg.first.nil? ? tmp_msg.first.edit(e) : raise
    event.drain
  rescue => e
    tmp_msg.first.edit('Failed to trace replays') if !tmp_msg.first.nil?
    event.drain
    lex(e, 'Failed to trace replays')
  end

  # Tests whether ntrace is working with this level or not
  def test_ntrace(ranks: [0], board: 'hs')
    leaderboard = vanilla.leaderboard(board, pluck: false)
    scores = ranks.map{ |r| leaderboard[r] }.compact
    return :other if scores.empty?

    # Export input files and run ntrace
    demos = scores.map{ |s| s.demo.demo }
    return :other if demos.count(nil) > 0
    File.binwrite('map_data', dump_level)
    demos.each_with_index.map{ |demo, i| File.binwrite("inputs_#{i}", demo) }
    shell("python3 #{PATH_NTRACE}")

    # Read output files
    file = File.binread('output.txt') rescue nil
    return :error if file.nil?
    valid = file.scan(/True|False/).map{ |b| b == 'True' }
    FileUtils.rm(['map_data', *Dir.glob('inputs_*'), 'output.txt'])
    return valid.count(false) == 0 ? :good : :bad
  rescue => e
    lex(e, 'ntrace testing failed')
    nil
  end
end

class Mappack < ActiveRecord::Base
  alias_attribute :scores,   :mappack_scores
  alias_attribute :levels,   :mappack_levels
  alias_attribute :episodes, :mappack_episodes
  alias_attribute :stories,  :mappack_stories
  alias_attribute :channels, :mappack_channels
  has_many :mappack_scores
  has_many :mappack_levels
  has_many :mappack_episodes
  has_many :mappack_stories
  has_many :mappack_channels
  enum tab: TABS_NEW.map{ |k, v| [k, v[:mode] * 7 + v[:tab]] }.to_h

  # Parse all mappacks in the mappack directory into the database
  #   update - Update preexisting mappacks (otherwise, only parses newly added ones)
  #   all    - Update all versions of each mappack
  #   hard   - Perform a hard update (see self.read)
  def self.seed(update: false, all: true, hard: false, discord: false)
    # Fetch mappacks
    perror("Mappacks directory not found, not seeding.", discord: discord) if !Dir.exist?(DIR_MAPPACKS)
    mappacks = {}
    Dir.entries(DIR_MAPPACKS).select{ |d| !!d[/\d+_.+/] }.sort.map{ |d|
      id, code, version = d.split('_')
      mappacks[code] = { id: id.to_i, versions: [] } if !mappacks.key?(code)
      mappacks[code][:id] = id.to_i
      mappacks[code][:versions] << version.to_i
    }

    # Integrity checks:
    # - Ensure no ID conflicts
    # - Ensure all versions are present
    mappacks.group_by{ |code, atts| atts[:id] }.each{ |id, packs|
      perror("Mappack ID conflict: #{packs.map{ |p| p[0].upcase }.join(', ')}.", discord: discord) if packs.size > 1
    }
    mappacks.each{ |code, atts|
      missing = (1 .. atts[:versions].max).to_a - atts[:versions]
      perror("#{code.upcase} missing versions #{missing.join(', ')}.", discord: discord) unless missing.empty?
    }

    # Read mappacks
    mappacks.each{ |code, atts|
      id       = atts[:id]
      versions = atts[:versions].sort

      versions.each{ |version|
        next if !all && version < versions.max
        mappack = Mappack.find_by(id: id)
        if mappack
          next unless update
          perror("Mappack with ID #{id} already belongs to #{mappack.code.upcase}.", discord: discord) if mappack.code.upcase != code.upcase
          if version < mappack.version
            if hard
              MappackData.joins('mappack_levels ON mappack_levels.id = highscoreable_id')
                         .where("mappack_id = #{id} AND version >= #{version}").delete_all
            else
              perror("Cannot soft update #{code.upcase} to v#{version} (already at v#{mappack.version}).", discord: discord)
            end
          end
          mappack.update(version: version)
          mappack.read(v: version, hard: hard, discord: discord)
        else
          perror("#{code.upcase} v1 should exist (trying to create v#{version}).", discord: discord) if version != 1
          Mappack.create(id: id, code: code, version: 1).read(v: 1, hard: true, discord: discord)
        end
      }
    }

    # Update mappack digest
    digest
  rescue => e
    lex(e, "Error seeding mappacks to database")
  end

  # Update the digest file, which summarizes mappack info into a file that can
  # be queried via the internet, containing the ID, code and version for each
  # mappack, one per line.
  def self.digest
    dig = Mappack.all.order(:id).pluck(:id, :code, :version).map{ |m|
      m.join(' ') + "\n"
    }.join
    File.write(PATH_MAPPACK_INFO, dig)
  rescue => e
    lex(e, 'Failed to generate mappack digest file')
  end

  # Return the folder that contains this mappack's files
  def folder(v: nil)
    if !v
      err("The mappack version needs to be provided.")
      return
    end

    dir = File.join(DIR_MAPPACKS, "#{"%03d" % [id]}_#{code}_#{v}")
    Dir.exist?(dir) ? dir : nil
  end

  # TODO: Parse challenge files, in a separate function with its own command,
  # which is also called from the general seed and read functions.

  # Parses map files corresponding to this mappack, and updates the database
  #   v       - Specifies the version of the mappack
  #   hard    - A hard update is aimed at versions with significant changes,
  #             e.g., different amount of maps. In this case, the highscoreables
  #             are deleted. For soft updates, checks of similarity are enforced,
  #             and a report of changes is printed.
  #   discord - Log errors back to Discord.
  def read(v: nil, hard: false, discord: false)
    # Integrity check for mappack version
    v = version || 1 if !v
    perror("Cannot soft update an older mappack version (#{v} vs #{version}).", discord: discord) if v < version && !hard
    name_str = "#{code.upcase} v#{v}"

    # Check for mappack directory
    log("Parsing mappack #{name_str}...")
    dir = folder(v: v)
    perror("Directory for mappack #{name_str} not found, not reading", discord: discord) if !dir

    # Fetch mappack files
    files = Dir.entries(dir).select{ |f|
      path = File.join(dir, f)
      File.file?(path) && File.extname(path) == ".txt"
    }.sort
    warn("No appropriate files found in directory for mappack #{name_str}") if files.count == 0

    if !hard
      # Soft updates: Ensure the new tabs will replace the old ones precisely
      tabs_old = MappackLevel.where(mappack_id: id).distinct.pluck('tab AS tab_int').sort
      tabs_new = files.map{ |f|
        tab = TABS_NEW.values.find{ |att| att[:files].key?(f[0..-5]) }
        tab ? tab[:mode] * 7 + tab[:tab] : nil
      }.compact.uniq.sort
      perror("Tabs for mappack #{code.upcase} do not coincide, cannot do soft update.", discord: discord) if tabs_old != tabs_new
    else
      # Hard updates: Delete highscoreables
      levels.delete_all(:delete_all)
      episodes.delete_all(:delete_all)
      stories.delete_all(:delete_all)
    end

    # Delete map data from newer versions
    MappackData.joins('INNER JOIN mappack_levels ON mappack_levels.id = highscoreable_id')
               .where("mappack_id = #{id} AND version >= #{v}").delete_all

    # Parse mappack files
    file_errors = 0
    map_errors = 0
    changes = { name: 0, tiles: 0, objects: 0 } if !hard
    files.each{ |f|
      # Find corresponding tab
      tab_code = f[0..-5]
      tab = TABS_NEW.values.find{ |att| att[:files].key?(tab_code) }
      if tab.nil?
        warn("Unrecognized file #{tab_code} parsing mappack #{name_str}")
        next
      end

      # Parse file
      maps = Map.parse_metanet_file(File.join(dir, f), tab[:files][tab_code], name_str)
      if maps.nil?
        file_errors += 1
        perror("Parsing of #{name_str} #{f} failed, ending soft update.", discord: discord) if !hard
        next
      end

      # Precompute some indices for the database
      mappack_offset = TYPES['Level'][:slots] * id
      file_index     = tab[:files].keys.index(tab_code)
      file_offset    = tab[:files].values.take(file_index).sum
      tab_offset     = tab[:start]
      tab_index      = tab[:mode] * 7 + tab[:tab]

      count = maps.count
      # In soft updates, map count must be the same (or smaller, if tab is
      # partitioned in multiple files, but never higher)
      perror("Map count in #{code.upcase} #{f} exceeds database ones, must do hard update.", discord: discord) if !hard && count > levels.where(tab: tab_index).count

      # Create new database records
      maps.each_with_index{ |map, map_offset|
        dbg("#{hard ? 'Creating' : 'Updating'} record #{"%-3d" % (map_offset + 1)} / #{count} from #{f} for mappack #{name_str}...", newline: false)
        if map.nil?
          map_errors += 1
          perror("Parsing of #{name_str} #{f} map #{map_offset} failed, ending soft update.", discord: discord) if !hard
          next
        end
        tab_id   = file_offset    + map_offset # ID of level within tab
        inner_id = tab_offset     + tab_id     # ID of level within mappack
        level_id = mappack_offset + inner_id   # ID of level in database

        # Create mappack level
        change_level = false
        if hard
          level = MappackLevel.find_or_create_by(id: level_id)
          change_level = true
        else
          level = MappackLevel.find_by(id: level_id)
          perror("#{code.upcase} level with ID #{level_id} should exist.", discord: discord) if !level
          if map[:title].strip != level.longname
            changes[:name] += 1
            change_level = true
          end
        end

        level.update(
          inner_id:   inner_id,
          mappack_id: id,
          mode:       tab[:mode],
          tab:        tab_index,
          episode_id: level_id / 5,
          name:       code.upcase + '-' + compute_name(inner_id, 0),
          longname:   map[:title].strip,
          gold:       map[:gold]
        ) if change_level

        # Save new mappack data (tiles and objects) if:
        #   Hard update - Always
        #   Soft update - Only when the map data is different
        prev_tiles = level.tile_data(version: v - 1)
        new_tiles  = Map.encode_tiles(map[:tiles])
        save_tiles = prev_tiles != new_tiles

        prev_objects = level.object_data(version: v - 1)
        new_objects  = Map.encode_objects(map[:objects])
        save_objects = prev_objects != new_objects

        new_data = hard || save_tiles || save_objects
        if new_data
          data = MappackData.find_or_create_by(highscoreable_id: level_id, version: v)
          if hard || save_tiles
            data.update(tile_data: new_tiles)
            changes[:tiles] += 1 if !hard
          end
          if hard || save_objects
            data.update(object_data: new_objects)
            changes[:objects] += 1 if !hard
          end
        end

        # Create corresponding mappack episode, except for secret tabs.
        next if tab[:secret] || level_id % 5 > 0
        story = tab[:mode] == 0 && (!tab[:x] || map_offset < 5 * tab[:files][tab_code] / 6)

        episode = MappackEpisode.find_by(id: level_id / 5)
        if hard
          episode = MappackEpisode.create(
            id:         level_id / 5,
            inner_id:   inner_id / 5,
            mappack_id: id,
            mode:       tab[:mode],
            tab:        tab_index,
            story_id:   story ? level_id / 25 : nil,
            name:       code.upcase + '-' + compute_name(inner_id / 5, 1)
          ) unless episode
        else
          perror("#{code.upcase} episode with ID #{level_id / 5} should exist, stopping soft update.", discord: discord) if !episode
        end

        # Create corresponding mappack story, only for non-X-Row Solo.
        next if !story || level_id % 25 > 0

        story = MappackStory.find_by(id: level_id / 25)
        if hard
          story = MappackStory.create(
            id:         level_id / 25,
            inner_id:   inner_id / 25,
            mappack_id: id,
            mode:       tab[:mode],
            tab:        tab_index,
            name:       code.upcase + '-' + compute_name(inner_id / 25, 2)
          ) unless story
        else
          perror("#{code.upcase} story with ID #{level_id / 25} should exist, stopping soft update.", discord: discord) if !story
        end
      }
      Log.clear

      # Log results for this file
      count = maps.count(nil)
      map_errors += count
      if count == 0
        dbg("Parsed file #{tab_code} for mappack #{name_str} without errors", pad: true)
      else
        warn("Parsed file #{tab_code} for mappack #{name_str} with #{count} errors", pad: true)
      end
    }

    # Fill in episode and story gold counts based on their corresponding levels
    episode_count = episodes.size
    episodes.find_each.with_index{ |e, i|
      dbg("Setting gold count for #{name_str} episode #{i + 1} / #{episode_count}...", progress: true)
      e.update(gold: MappackLevel.where(episode: e).sum(:gold))
    }
    Log.clear
    story_count = stories.size
    stories.find_each.with_index{ |s, i|
      dbg("Setting gold count for #{name_str} story #{i + 1} / #{story_count}...", progress: true)
      s.update(gold: MappackEpisode.where(story: s).sum(:gold))
    }
    Log.clear

    # Update precomputed SHA1 hashes
    MappackLevel.update_hashes(mappack: self)
    MappackEpisode.update_hashes(mappack: self, pre: true)
    MappackStory.update_hashes(mappack: self, pre: true)

    # Log final results for entire mappack
    if file_errors + map_errors == 0
      succ("Successfully parsed mappack #{name_str}")
      self.update(version: v)
    else
      warn("Parsed mappack #{name_str} with #{file_errors} file errors and #{map_errors} map errors")
    end
    dbg("Soft update: #{changes[:name]} name changes, #{changes[:tiles]} tile changes, #{changes[:objects]} object changes.") if !hard
  rescue => e
    lex(e, "Error reading mappack #{name_str}")
  end

  # Read the author list and write to the db
  def read_authors(v: nil)
    v = version || 1 if !v

    # Integrity checks
    dir = folder(v: v)
    if !dir
      err("Directory for mappack #{verbatim(code)} not found")
      return
    end
    path = File.join(dir, FILENAME_MAPPACK_AUTHORS)
    if !File.file?(path)
      err("Authors file for mappack #{verbatim(code)} not found")
      return
    end

    # Parse authors file
    file = File.binread(path)
    names = file.split("\n").map(&:strip)
    maps = levels.order(:id)
    if maps.size != names.size
      err("Authors file for mappack #{verbatim(code)} has incorrect length (#{names.size} names vs #{maps.size} maps)")
      return
    end

    # Write names
    count = maps.size
    maps.each_with_index{ |m, i|
      dbg("Adding author #{i + 1} / #{count}...", pad: true, newline: false)
      m.update(author: names[i])
    }
    Log.clear
  rescue => e
    lex(e, "Failed to read authors file for mappack #{verbatim(code)}")
  end

  # Check additional requirements for scores submitted to this mappack
  # For instance, w's Duality coop pack requires that the replays for both
  # players be identical
  def check_requirements(demos)
    case self.code
    when 'dua'
      demos.each{ |d|
        # Demo must have even length (coop)
        sz = d.size
        if sz % 2 == 1
          warn("Demo does not satisfy Duality's requirements (odd length)")
          return false
        end

        # Both halves of the demo must be identical
        if d[0...sz / 2] != d[sz / 2..-1]
          warn("Demo does not satisfy Duality's requirements (different inputs)")
          return false
        end
      }
      true
    else
      true
    end
  rescue => e
    lex(e, "Failed to check requirements for demo in '#{code}' mappack")
    false
  end

  # Set some of the mappack's info on command, which isn't parsed from the files
  def set_info(name: nil, author: nil, date: nil, channel: nil, version: nil)
    self.update(name: name) if name
    self.update(authors: author) if author
    self.update(version: version) if version
    self.update(date: Time.strptime(date, '%Y/%m/%d').strftime(DATE_FORMAT_MYSQL)) if date
    channel.each{ |c|
      if is_num(c)
        ch = find_channel(id: c.strip.to_i)
      else
        ch = find_channel(name: c.strip)
      end
      perror("No channel found by the name #{verbatim(c.strip)}.") if !ch
      chn = MappackChannel.find_or_create_by(id: ch.id)
      channels << chn
      chn.update(name: ch.name)
    } if channel
  rescue => e
    lex(e, "Failed to set mappack '#{code}' info")
    nil
  end
end

class MappackData < ActiveRecord::Base
  alias_attribute :level, :mappack_level
  belongs_to :mappack_level, foreign_key: :highscoreable_id
end

module MappackHighscoreable
  include Highscoreable

  def type
    self.class.to_s
  end

  def version
    versions.max
  end

  # Recompute SHA1 hash for all available versions
  # If 'pre', then episodes/stories will not recompute their level hashes
  def update_hashes(pre: false)
    hashes.clear
    versions.each{ |v|
      hashes.create(version: v, sha1_hash: hash(c: true, v: v, pre: pre))
    }
    hashes.count
  end

  # Return leaderboards, filtering obsolete scores and sorting appropiately
  # depending on the mode (hs / sr).
  # Optionally 
  def leaderboard(
      m         = 'hs',  # Playing mode (hs, sr, gm)
      score     = false, # Sort by score and date instead of rank (used for computing the rank)
      truncate:   20,    # How many scores to take (0 = all)
      pluck:      true,  # Pluck or keep Rails relation
      aliases:    false, # Use player names or display names
      metanet_id: nil,   # Player making the request if coming from CLE
      page:       0      # Index of page to fetch
    )
    m = 'hs' if !['hs', 'sr', 'gm'].include?(m)
    names = aliases ? 'IF(display_name IS NOT NULL, display_name, name)' : 'name'
    attr_names = %W[id score_#{m} name metanet_id]

    # Check if a manual replay ID has been set, so that we only select that one
    manual = GlobalProperty.find_by(key: 'replay_id').value rescue nil
    use_manual = manual && metanet_id == BOTMASTER_NPP_ID

    # Handle manual board
    if use_manual
      attrs = %W[mappack_scores.id score_#{m} #{names} metanet_id]
      board = scores.where(id: manual)
    end

    # Handle standard boards
    if ['hs', 'sr'].include?(m) && !use_manual
      attrs = %W[mappack_scores.id score_#{m} #{names} metanet_id]
      board = scores.where("rank_#{m} IS NOT NULL")
      if score
        board = board.order("score_#{m} #{m == 'hs' ? 'DESC' : 'ASC'}, date ASC")
      else
        board = board.order("rank_#{m} ASC")
      end
    end

    # Handle gold boards
    if m == 'gm' && !use_manual
      attrs = [
        'MIN(subquery.id) AS id',
        'MIN(score_gm) AS score_gm',
        "MIN(#{names}) AS name",
        'subquery.metanet_id'
      ]
      join = %{
        INNER JOIN (
          SELECT metanet_id, MIN(gold) AS score_gm
          FROM mappack_scores
          WHERE highscoreable_id = #{id} AND highscoreable_type = '#{type}'
          GROUP BY metanet_id
        ) AS opt
        ON mappack_scores.metanet_id = opt.metanet_id AND gold = score_gm
      }.gsub(/\s+/, ' ').strip
      subquery = scores.select(:id, :score_gm, :player_id, :metanet_id).joins(join)
      board = MappackScore.from(subquery).group(:metanet_id).order('score_gm', 'id')
    end

    # Paginate (offset and truncate), fetch player names, and convert to hash
    board = board.offset(20 * page) if page > 0
    board = board.limit(truncate) if truncate > 0
    return board if !pluck
    board.joins("INNER JOIN players ON players.id = player_id")
         .pluck(*attrs).map{ |s| attr_names.zip(s).to_h }
  end

  # Return scores in JSON format expected by N++
  def get_scores(qt = 0, metanet_id = nil)
    # Determine leaderboard type
    page = 0
    case qt
    when 0
      m = 'hs'
    when 1
      m = 'hs'
      #page = 1 if metanet_id == BOTMASTER_NPP_ID
    when 2
      m = 'sr'
    end

    # Fetch scores
    board = leaderboard(m, metanet_id: metanet_id, page: page)

    # Build response
    res = {}

    #score = board.find_by(metanet_id: metanet_id) if !metanet_id.nil?
    #res["userInfo"] = {
    #  "my_score"        => m == 'hs' ? (1000 * score["score_#{m}"].to_i / 60.0).round : 1000 * score["score_#{m}"].to_i,
    #  "my_rank"         => (score["rank_#{m}"].to_i rescue -1),
    #  "my_replay_id"    => score.id.to_i,
    #  "my_display_name" => score.player.name.to_s.remove("\\")
    #} if !score.nil?

    res["scores"] = board.each_with_index.map{ |s, i|
      {
        "score"     => m == 'hs' ? (1000 * s["score_#{m}"].to_i / 60.0).round : 1000 * s["score_#{m}"].to_i,
        "rank"      => 20 * page + i,
        "user_id"   => s['metanet_id'].to_i,
        "user_name" => s['name'].to_s.remove("\\"),
        "replay_id" => s['id'].to_i
      }
    }

    res["query_type"] = qt
    res["#{self.class.to_s.remove("Mappack").downcase}_id"] = self.inner_id

    # Log
    player = Player.find_by(metanet_id: metanet_id)
    if !player.nil? && !player.name.nil?
      text = "#{player.name.to_s} requested #{self.name} leaderboards"
    else
      text = "#{self.name} leaderboards requested"
    end
    dbg(res.to_json) if SOCKET_LOG
    dbg(text)

    # Return leaderboards
    res.to_json
  end

  # Updates the rank and tied_rank fields of a specific mode, necessary when
  # there's a new score (or when one is deleted later).
  # Returns the rank of a specific player, if the player_id is passed
  def update_ranks(mode = 'hs', player_id = nil)
    return -1 if !['hs', 'sr'].include?(mode)
    rank = -1
    board = leaderboard(mode, true, truncate: 0, pluck: false)
    tied_score = board[0]["score_#{mode}"]
    tied_rank = 0
    board.each_with_index{ |s, i|
      rank = i if !player_id.nil? && s.player_id == player_id
      score = mode == 'hs' ? s.score_hs : s.score_sr
      if mode == 'hs' ? score < tied_score : score > tied_score
        tied_rank = i
        tied_score = score
      end
      s.update("rank_#{mode}".to_sym => i, "tied_rank_#{mode}".to_sym => tied_rank)
    }
    rank
  rescue
    -1
  end

  # Delete all the scores that aren't keepies (were never a hs/sr PB),
  # and which no longer have the max/min amount of gold collected.
  # If a player is not specified, do this operation for all players present
  # in this highscoreable.
  def delete_obsoletes(player = nil)
    if player
      ids = [player.id]
    else
      ids = scores.group(:player_id).pluck(:player_id)
    end

    ids.each{ |pid|
      score_list = scores.where(player_id: pid)
      gold_max = score_list.maximum(:gold)
      gold_min = score_list.minimum(:gold)
      pb_hs = nil # Highscore PB
      pb_sr = nil # Speedrun PB
      keepies = []
      score_list.order(:id).each{ |s|
        keepie = false
        if pb_hs.nil? || s.score_hs > pb_hs
          pb_hs = s.score_hs
          keepie = true
        end
        if pb_sr.nil? || s.score_sr < pb_sr
          pb_sr = s.score_sr
          keepie = true
        end
        keepies << s.id if keepie
      }
      score_list.where(rank_hs: nil, rank_sr: nil)
                .where("gold < #{gold_max} AND gold > #{gold_min}")
                .where.not(id: keepies)
                .each(&:wipe)
    }
    true
  rescue => e
    lex(e, 'Failed to delete obsolete scores.')
    false
  end

  # Verifies the integrity of a replay by generating the security hash and
  # comparing it with the submitted one.
  #
  # The format used by N++ is:
  #   Hash = SHA1(MapHash + ScoreString)
  # where:
  #   MapHash = SHA1(Pwd + MapData) [see Map#hash]
  #       Pwd     = Hardcoded password (not present in outte's source code)
  #       MapData = Map's data [see Map#dump_level(hash: true)]
  #   ScoreString = (Score * 1000) rounded as an integer
  #
  # Notes:
  #   - Since this depends on both the score and the map data, a score cannot
  #     be submitted if either have been tampered with.
  #   - The modulo 2 ** 32 is to simulate 4-byte unsigned integer arithmetic,
  #     which is what N++ uses. Negative scores (which sometimes happen erroneously)
  #     then underflow, so we need to replicate this behaviour to match the hashes.
  def _verify_replay(ninja_check, score, c: true, v: nil)
    c_hash = hashes.find_by(version: v)
    map_hash = c && c_hash ? c_hash.sha1_hash : hash(c: c, v: v)
    return true if !map_hash
    score = ((1000.0 * score / 60.0 + 0.5).floor % 2 ** 32).to_s
    sha1(map_hash + score, c: c) == ninja_check
  end

  def verify_replay(ninja_check, score, all: true)
    (all ? versions : [version]).each{ |v|
      #return true if _verify_replay(ninja_check, score, v: v, c: false)
      return true if _verify_replay(ninja_check, score, v: v, c: true)
    }
    false
  end
end

class MappackLevel < ActiveRecord::Base
  include Map
  include MappackHighscoreable
  include Levelish
  alias_attribute :scores, :mappack_scores
  alias_attribute :hashes, :mappack_hashes
  alias_attribute :episode, :mappack_episode
  has_many :mappack_scores, as: :highscoreable
  has_many :mappack_hashes, as: :highscoreable, dependent: :delete_all
  belongs_to :mappack
  belongs_to :mappack_episode, foreign_key: :episode_id
  enum tab: TABS_NEW.map{ |k, v| [k, v[:mode] * 7 + v[:tab]] }.to_h

  def self.mappack
    MappackLevel
  end

  def self.vanilla
    Level
  end

  # Update all mappack level SHA1 hashes (for every version)
  # 'pre' parameter is unused (as we force it to false, since we always want
  # to recompute the level hashes), but is left there for compatibility with the
  # Episode/Story versions of this method
  def self.update_hashes(mappack: nil, pre: false)
    total = 0
    list = self.where(mappack ? "mappack_id = #{mappack.id}" : '')
    count = list.count
    list.find_each.with_index{ |l, i|
      dbg("Updating mappack hashes for level #{i + 1} / #{count}...", progress: true)
      total += l.update_hashes(pre: false)
    }
    Log.clear
    total
  end

  def versions
    MappackData.where(highscoreable_id: id)
               .where("tile_data IS NOT NULL OR object_data IS NOT NULL")
               .distinct
               .order(:version)
               .pluck(:version)
  end

  # Return the tile data, optionally specify a version, otherwise pick last
  # Can also return all available versions as a hash
  def tile_data(version: nil, all: false)
    data = MappackData.where(highscoreable_id: id)
                      .where(version ? "version <= #{version}" : '')
                      .where.not(tile_data: nil)
    return nil if data.empty?

    if all
      data.pluck(:version, :tile_data).to_h
    else
      data.order(version: :desc).first.tile_data
    end
  rescue
    nil
  end

  # Return the object data, optionally specify a version, otherwise pick last
  # Can also return all available versions as a hash
  def object_data(version: nil, all: false)
    data = MappackData.where(highscoreable_id: id)
                      .where(version ? "version <= #{version}" : '')
                      .where.not(object_data: nil)
    return nil if data.empty?

    if all
      data.pluck(:version, :object_data).to_h
    else
      data.order(version: :desc).first.object_data
    end
  rescue
    nil
  end

  # Compare hashes generated by Ruby and STB
  def compare_hashes
    # Prepare map data to hash
    map_data = dump_level(hash: true)
    return true if map_data.nil?
    to_hash = PWD + map_data[0xB8..-1]

    # Hash
    hash_c = sha1(to_hash, c: true)
    hash_ruby = sha1(to_hash, c: false)
    return false if !hash_c || !hash_ruby

    return hash_c == hash_ruby
  end
end

class MappackEpisode < ActiveRecord::Base
  include MappackHighscoreable
  include Episodish
  alias_attribute :levels, :mappack_levels
  alias_attribute :scores, :mappack_scores
  alias_attribute :hashes, :mappack_hashes
  alias_attribute :story, :mappack_story
  alias_attribute :tweaks, :mappack_scores_tweaks
  has_many :mappack_levels, foreign_key: :episode_id
  has_many :mappack_scores, as: :highscoreable
  has_many :mappack_hashes, as: :highscoreable, dependent: :delete_all
  has_many :mappack_scores_tweaks, foreign_key: :episode_id
  belongs_to :mappack
  belongs_to :mappack_story, foreign_key: :story_id
  enum tab: TABS_NEW.map{ |k, v| [k, v[:mode] * 7 + v[:tab]] }.to_h

  def self.mappack
    MappackEpisode
  end

  def self.vanilla
    Episode
  end

  # Update all mappack episode SHA1 hashes (for every version)
  def self.update_hashes(mappack: nil, pre: false)
    total = 0
    list = self.where(mappack ? "mappack_id = #{mappack.id}" : '')
    count = list.count
    list.find_each.with_index{ |e, i|
      dbg("Updating mappack hashes for episode #{i + 1} / #{count}...", progress: true)
      total += e.update_hashes(pre: pre)
    }
    Log.clear
    total
  end

  def versions
    MappackData.where("highscoreable_id DIV 5 = #{id}")
               .where("tile_data IS NOT NULL OR object_data IS NOT NULL")
               .distinct
               .order(:version)
               .pluck(:version)
  end

  # Computes the episode's hash, which the game uses for integrity verifications
  # If 'pre', take the precomputed level hashes, otherwise compute them
  def hash(c: false, v: nil, pre: false)
    hashes = levels.order(:id).map{ |l|
      stored = l.hashes.where("version <= #{v}").order(:version).last
      binding.pry if !stored
      c && pre && stored ? stored.sha1_hash : l.hash(c: c, v: v)
    }.compact
    hashes.size < 5 ? nil : hashes.join
  end
end

class MappackStory < ActiveRecord::Base
  include MappackHighscoreable
  include Storyish
  alias_attribute :episodes, :mappack_episodes
  alias_attribute :scores, :mappack_scores
  alias_attribute :hashes, :mappack_hashes
  has_many :mappack_episodes, foreign_key: :story_id
  has_many :mappack_scores, as: :highscoreable
  has_many :mappack_hashes, as: :highscoreable, dependent: :delete_all
  belongs_to :mappack
  enum tab: TABS_NEW.map{ |k, v| [k, v[:mode] * 7 + v[:tab]] }.to_h

  def self.mappack
    MappackStory
  end

  def self.vanilla
    Story
  end

  # Update all mappack story SHA1 hashes (for every version)
  def self.update_hashes(mappack: nil, pre: false)
    total = 0
    list = self.where(mappack ? "mappack_id = #{mappack.id}" : '')
    count = list.count
    list.find_each.with_index{ |s, i|
      dbg("Updating mappack hashes for story #{i + 1} / #{count}...", progress: true)
      total += s.update_hashes(pre: pre)
    }
    Log.clear
    total
  end

  def versions
    MappackData.where("highscoreable_id DIV 25 = #{id}")
               .where("tile_data IS NOT NULL OR object_data IS NOT NULL")
               .distinct
               .order(:version)
               .pluck(:version)
  end

  # Computes the story's hash, which the game uses for integrity verifications
  # If 'pre', take the precomputed level hashes, otherwise compute them
  def hash(c: false, v: nil, pre: false)
    hashes = levels.order(:id).map{ |l|
      stored = l.hashes.where("version <= #{v}").order(:version).last
      c && pre && stored ? stored.sha1_hash : l.hash(c: c, v: v)
    }.compact
    return nil if hashes.size < 25
    work = 0.chr * 20
    25.times.each{ |i|
      work = sha1(work + hashes[i], c: c)
    }
    work
  end
end

class MappackScore < ActiveRecord::Base
  include Scorish
  alias_attribute :demo,    :mappack_demo
  alias_attribute :scores,  :mappack_scores
  alias_attribute :level,   :mappack_level
  alias_attribute :episode, :mappack_episode
  alias_attribute :story,   :mappack_story
  has_one :mappack_demo, foreign_key: :id
  belongs_to :player
  belongs_to :highscoreable, polymorphic: true
  belongs_to :mappack
  enum tab: TABS_NEW.map{ |k, v| [k, v[:mode] * 7 + v[:tab]] }.to_h

  # TODO: Add integrity checks and warnings in Demo.parse

  # Verify, parse and save a submitted run, respond suitably
  def self.add(code, query, req = nil)
    # Parse player ID
    uid = query['user_id'].to_i
    if uid <= 0 || uid >= 10000000
      warn("Invalid player (ID #{uid}) submitted a score")
      return
    end

    # Apply blacklist
    name = "ID:#{uid}"
    if BLACKLIST.key?(uid)
      warn("Blacklisted player #{BLACKLIST[uid][0]} submitted a score", discord: true)
      return
    end

    # Parse type
    type = TYPES.find{ |_, h| query.key?("#{h[:name].downcase}_id") }[1] rescue nil
    if type.nil?
      warn("Score submitted: Type not found")
      return
    end
    id_field = "#{type[:name].downcase}_id"

    # Craft response fields
    res = {
      'better'    => 0,
      'score'     => query['score'].to_i,
      'rank'      => -1,
      'replay_id' => -1,
      'user_id'   => uid,
      'qt'        => query['qt'].to_i,
      id_field    => query[id_field].to_i
    }

    # Find player
    player = Player.find_or_create_by(metanet_id: uid)
    name = !player.name.nil? ? player.name : "ID:#{player.metanet_id}"

    # Find mappack
    mappack = Mappack.find_by(code: code)
    if mappack.nil?
      warn("Score submitted by #{name}: Mappack '#{code}' not found")
      return
    end

    # Find highscoreable
    sid = query[id_field].to_i
    h = "Mappack#{type[:name]}".constantize.find_by(mappack: mappack, inner_id: sid)
    if h.nil?
      # If highscoreable not found, and forwarding is disabled, return nil
      if !CLE_FORWARD
        warn("Score submitted by #{name}: #{type[:name]} ID:#{sid} for mappack '#{code}' not found")
        return
      end

      # If highscoreable not found, but forwarding is enabled, forward to Metanet
      # Also, try to update the corresponding Metanet scores in outte (in parallel)
      res = forward(req)
      _thread(release: true) do
        h = (sid >= MIN_ID ? Userlevel : type[:name].constantize).find_by(id: sid)
        h.update_scores(fast: true) if h
      end if !res.nil?
      return res
    end

    # Parse demos and compute new scores
    demos = Demo.parse(query['replay_data'], type[:name])
    score_hs = (60.0 * query['score'].to_i / 1000.0).round
    score_sr = demos.map(&:size).sum
    score_sr /= 2 if h.mode == 1 # Coop demos contain 2 sets of inputs

    # Tweak level scores submitted within episode runs
    score_hs_orig = score_hs
    if type[:name] == 'Level'
      score_hs = MappackScoresTweak.tweak(score_hs, player, h, Demo.parse_header(query['replay_data']))
      if score_hs.nil?
        warn("Tweaking of score submitted by #{name} to #{h.name} failed", discord: true)
        score_hs = score_hs_orig
      end
    end

    # Compute gold count from hs and sr scores
    goldf = MappackScore.gold_count(type[:name], score_hs, score_sr)
    gold = goldf.round # Save floating value for later

    # Verify replay integrity by checking security hash
    legit = h.verify_replay(query['ninja_check'], score_hs_orig)
    return if INTEGRITY_CHECKS && !legit

    # Verify additional mappack-wise requirements
    return if !mappack.check_requirements(demos)

    # Fetch old PB's
    scores = MappackScore.where(highscoreable: h, player: player)
    score_hs_max = scores.maximum(:score_hs)
    score_sr_min = scores.minimum(:score_sr)
    gold_max = scores.maximum(:gold)
    gold_min = scores.minimum(:gold)

    # Determine if new score is better and has to be saved
    res['better'] = 0
    hs = false
    sr = false
    gp = false
    gm = false
    if score_hs_max.nil? || score_hs > score_hs_max
      scores.update_all(rank_hs: nil, tied_rank_hs: nil)
      res['better'] = 1
      hs = true
    end
    if score_sr_min.nil? || score_sr < score_sr_min
      scores.update_all(rank_sr: nil, tied_rank_sr: nil)
      sr = true
    end
    if gold_max.nil? || gold > gold_max
      gp = true
      gold_max = gold
    end
    if gold_min.nil? || gold < gold_min
      gm = true
      gold_min = gold
    end

    # If score improved in either mode
    id = -1
    if hs || sr || gp || gm
      # Create new score and demo
      score = MappackScore.create(
        rank_hs:       hs ? -1 : nil,
        tied_rank_hs:  hs ? -1 : nil,
        rank_sr:       sr ? -1 : nil,
        tied_rank_sr:  sr ? -1 : nil,
        score_hs:      score_hs,
        score_sr:      score_sr,
        mappack_id:    mappack.id,
        tab:           h.tab,
        player:        player,
        metanet_id:    player.metanet_id,
        highscoreable: h,
        date:          Time.now.strftime(DATE_FORMAT_MYSQL),
        gold:          gold
      )
      id = score.id
      MappackDemo.create(id: id, demo: Demo.encode(demos))

      # Verify hs score integrity by checking calculated gold count
      if (!MappackScore.verify_gold(goldf) && type[:name] != 'Story') || (h.gold && gold > h.gold)
        _thread do
          warn("Potentially incorrect hs score submitted by #{name} in #{h.name} (ID #{score.id})", discord: true)
        end
      end

      # Warn if the score submitted failed the map data integrity checks, and save it
      # to analyze it later (and possibly polish the hash algorithm)
      if !legit
        BadHash.find_or_create_by(id: id).update(
          npp_hash: query['ninja_check'],
          score: score_hs_orig
        )
        _thread do
          warn("Score submitted by #{name} to #{h.name} has invalid security hash", discord: true)
        end
      end

      # Warn if mappack version is outdated
      v1 = (req.path.split('/')[1][/\d+$/i] || 1).to_i
      v2 = mappack.version
      if WARN_VERSION && v1 != v2
        _thread do
          warn("#{name} submitted a score to #{h.name} with an incorrect mappack version (#{v1} vs #{v2})", discord: true)
        end
      end
    end

    # Update ranks and completions if necessary
    h.update_ranks('hs') if hs
    h.update_ranks('sr') if sr
    h.update(completions: h.scores.where.not(rank_hs: nil).count) if hs || sr

    # Delete obsolete scores of the player in the highscoreable
    h.delete_obsoletes(player)

    # Fetch player's best scores, to fill remaining response fields
    best_hs = MappackScore.where(highscoreable: h, player: player)
                          .where.not(rank_hs: nil)
                          .order(rank_hs: :asc)
                          .first
    best_sr = MappackScore.where(highscoreable: h, player: player)
                          .where.not(rank_sr: nil)
                          .order(rank_sr: :asc)
                          .first
    rank_hs = best_hs.rank_hs rescue nil
    rank_sr = best_sr.rank_sr rescue nil
    replay_id_hs = best_hs.id rescue nil
    replay_id_sr = best_sr.id rescue nil
    res['rank'] = rank_hs || rank_sr || -1
    res['replay_id'] = replay_id_hs || replay_id_sr || -1

    # Finish
    dbg(res.to_json) if SOCKET_LOG
    dbg("#{name} submitted a score to #{h.name}")
    return res.to_json
  rescue => e
    lex(e, "Failed to add score submitted by #{name} to mappack '#{code}'")
    return
  end

  # Respond to a request for leaderboards
  def self.get_scores(code, query, req = nil)
    name = "?"

    # Parse type
    type = TYPES.find{ |_, h| query.key?("#{h[:name].downcase}_id") }[1] rescue nil
    if type.nil?
      warn("Getting scores: Type not found")
      return
    end
    sid = query["#{type[:name].downcase}_id"].to_i
    name = "ID:#{sid}"

    # Find mappack
    mappack = Mappack.find_by(code: code)
    if mappack.nil?
      warn("Getting scores: Mappack '#{code}' not found")
      return
    end

    # Find highscoreable
    h = "Mappack#{type[:name]}".constantize.find_by(mappack: mappack, inner_id: sid)
    if h.nil?
      return forward(req) if CLE_FORWARD
      warn("Getting scores: #{type[:name]} #{name} for mappack '#{code}' not found")
      return
    end
    name = h.name

    # Get scores
    return h.get_scores(query['qt'].to_i, query['user_id'].to_i)
  rescue => e
    lex(e, "Failed to get scores for #{name} in mappack '#{code}'")
    return
  end

  # Respond to a request for a replay
  def self.get_replay(code, query, req = nil)
    # Integrity checks
    if !query.key?('replay_id')
      warn("Getting replay: Replay ID not provided")
      return
    end

    # Parse type (no type = level)
    type = TYPES.find{ |_, h| query['qt'].to_i == h[:qt] }[1] rescue nil
    if type.nil?
      warn("Getting replay: Type #{query['qt'].to_i} is incorrect")
      return
    end

    # Find mappack
    mappack = Mappack.find_by(code: code)
    if mappack.nil?
      warn("Getting replay: Mappack '#{code}' not found")
      return
    end

    # Find player (for logging purposes only)
    player = Player.find_by(metanet_id: query['user_id'].to_i)
    name = !player.nil? ? player.name : "ID:#{query['user_id']}"

    # Find score and perform integrity checks
    score = MappackScore.find_by(id: query['replay_id'].to_i)
    if score.nil?
      return forward(req) if CLE_FORWARD
      warn("Getting replay: Score with ID #{query['replay_id']} not found")
      return
    end

    if score.highscoreable.mappack.code != code
      return forward(req) if CLE_FORWARD
      warn("Getting replay: Score with ID #{query['replay_id']} is not from mappack '#{code}'")
      return
    end

    if score.highscoreable.type.remove('Mappack') != type[:name]
      return forward(req) if CLE_FORWARD
      warn("Getting replay: Score with ID #{query['replay_id']} is not from a #{type[:name].downcase}")
      return
    end

    # Find replay
    demo = score.demo
    if demo.nil? || demo.demo.nil?
      warn("Getting replay: Replay with ID #{query['replay_id']} not found")
      return
    end

    # Return replay
    dbg("#{name} requested replay #{query['replay_id']}")
    score.dump_replay
  rescue => e
    lex(e, "Failed to get replay with ID #{query['replay_id']} from mappack '#{code}'")
    return
  end

  # Manually change a score, given either:
  # - A player and a highscoreable, in which case, his current hs PB will be taken
  # - An ID, in which case that specific score will be chosen
  # It performs score validation via gold check before changing it
  def self.patch_score(id, highscoreable, player, score)
    # Find score
    if !id.nil? # If ID has been provided
      s = MappackScore.find_by(id: id)
      perror("Mappack score of ID #{id} not found") if score.nil?
      highscoreable = s.highscoreable
      player = s.player
      scores = MappackScore.where(highscoreable: highscoreable, player: player)
      perror("#{player.name} does not have a score in #{highscoreable.name}") if scores.empty?
    else # If highscoreable and player have been provided
      perror("#{highscoreable.name} does not belong to a mappack") if !highscoreable.is_a?(MappackHighscoreable)
      scores = self.where(highscoreable: highscoreable, player: player)
      perror("#{player.name} does not have a score in #{highscoreable.name}") if scores.empty?
      s = scores.where.not(rank_hs: nil).first
      perror("#{player.name}'s leaderboard score in #{highscoreable.name} not found") if s.nil?
    end

    # Score integrity checks
    new_score = (score * 60).round
    gold = MappackScore.gold_count(highscoreable.type, new_score, s.score_sr)
    perror("That score is incompatible with the framecount") if !MappackScore.verify_gold(gold) && !highscoreable.type.include?('Story')

    # Change score
    old_score = s.score_hs.to_f / 60.0
    perror("#{player.name}'s score (#{s.id}) in #{highscoreable.name} is already #{'%.3f' % old_score}") if s.score_hs == new_score
    s.update(score_hs: new_score, gold: gold.round)

    # Update player's ranks
    scores.update_all(rank_hs: nil, tied_rank_hs: nil)
    max = scores.where(score_hs: scores.pluck(:score_hs).max).order(:date).first
    max.update(rank_hs: -1, tied_rank_hs: -1) if max

    # Update global ranks
    highscoreable.update_ranks('hs')
    succ("Patched #{player.name}'s score (#{s.id}) in #{highscoreable.name} from #{'%.3f' % old_score} to #{'%.3f' % score}")
  rescue => e
    lex(e, 'Failed to patch score')
  end

  # Calculate gold count from hs and sr scores
  # We return a FLOAT, not an integer. See the next function for details.
  def self.gold_count(type, score_hs, score_sr)
    type = type.remove('Mappack')
    case type
    when 'Level'
      tweak = 1
    when 'Episode'
      tweak = 5
    when 'Story'
      tweak = 25
    else
      warn("Incorrect type when calculating gold count")
      tweak = 0
    end
    (score_hs + score_sr - 5400 - tweak).to_f / 120
  end

  # Verify if floating point gold count is close enough to an integer.
  #
  # Context: Sometimes the hs score is incorrectly calculated by the game,
  # and we can use this as a test to find incorrect scores, if the calculated
  # gold count is not exactly an integer.
  def self.verify_gold(gold)
    (gold - gold.round).abs < 0.001
  end

  # Perform the gold check (see the 2 methods above) for every score in the
  # database, returning the scores failing the check.
  def self.gold_check(id: MIN_REPLAY_ID, mappack: nil, strict: false)
    self.joins('INNER JOIN mappack_levels ON mappack_levels.id = highscoreable_id')
        .joins('INNER JOIN players on players.id = player_id')
        .where("highscoreable_type = 'MappackLevel' AND mappack_scores.id >= #{id}")
        .where(mappack ? "mappack_scores.mappack_id = #{mappack.id}" : '')
        .where(strict ? "rank_hs < 20 OR rank_sr < 20" : '')
        .having('remainder > 0.001')
        .order('highscoreable_id', 'mappack_scores.id')
        .pluck(
          'mappack_levels.name',
          'SUBSTRING(players.name, 1, 16)',
          'mappack_scores.id',
          'score_hs / 60.0',
          'rank_hs',
          'rank_sr',
          'ABS(MOD((score_hs + score_sr - 5401) / 120, 1)) AS remainder'
        ).map{ |row| row[0..-2] }
  rescue => e
    lex(e, 'Failed to compute gold check.')
    [['Error', 'Error', 'Error', 'Error', 'Error', 'Error']]
  end

  # Update the completion count for each mappack highscoreable, should only
  # need to be executed once, or occasionally, to seed them for the first
  # time. From then on, the score submission function updates the figure.
  def self.update_completions(mappack: nil)
    bench(:start) if BENCHMARK
    [MappackLevel, MappackEpisode, MappackStory].each{ |type|
      self.where(highscoreable_type: type).where.not(rank_hs: nil)
          .where(mappack ? "mappack_id = #{mappack.id}" : '')
          .group(:highscoreable_id)
          .order('count(highscoreable_id)', 'highscoreable_id')
          .count(:highscoreable_id)
          .group_by{ |id, count| count }
          .map{ |count, ids| [count, ids.map(&:first)] }
          .each{ |count, ids|
            type.where(id: ids).update_all(completions: count)
          }
    }
    bench(:step) if BENCHMARK
  end

  def archive
    self
  end

  def gold_count
    self.class.gold_count(highscoreable.type, score_hs, score_sr)
  end

  def verify_gold
    self.class.verify_gold(gold_count)
  end

  # Dumps demo data in the format N++ uses for server communications
  def dump_demo
    demos = Demo.decode(demo.demo, true)
    highscoreable.dump_demo(demos)
  rescue => e
    lex(e, "Failed to dump demo with ID #{id}")
    nil
  end

  # Dumps replay data (header + compressed demo data) in format used by N++
  def dump_replay
    type = TYPES[highscoreable.class.to_s.remove('Mappack')]

    # Build header
    replay = [type[:rt]].pack('L<')               # Replay type (0 lvl/sty, 1 ep)
    replay << [id].pack('L<')                     # Replay ID
    replay << [highscoreable.inner_id].pack('L<') # Level ID
    replay << [player.metanet_id].pack('L<')      # User ID

    # Append replay and return
    inputs = dump_demo
    return if inputs.nil?
    replay << Zlib::Deflate.deflate(inputs, 9)
    replay
  rescue => e
    lex(e, "Failed to dump replay with ID #{id}")
    return
  end

  # Deletes a score, with the necessary cleanup (delete demo, and update ranks if necessary)
  def wipe
    # Save attributes before destroying the object
    hs = rank_hs != nil
    sr = rank_sr != nil
    h = highscoreable
    p = player

    # Destroy demo and score
    demo.destroy
    self.destroy

    # Update rank fields, if the score was actually on the boards
    scores = h.scores.where(player: p) if hs || sr

    if hs
      scores.update_all(rank_hs: nil, tied_rank_hs: nil)
      max = scores.where(score_hs: scores.pluck(:score_hs).max).order(:date).first
      max.update(rank_hs: -1, tied_rank_hs: -1) if max
      h.update_ranks('hs')
    end

    if sr
      scores.update_all(rank_sr: nil, tied_rank_sr: nil)
      min = scores.where(score_sr: scores.pluck(:score_sr).min).order(:date).first
      min.update(rank_sr: -1, tied_rank_sr: -1) if min
      h.update_ranks('sr')
    end

    true
  rescue => e
    lex(e, 'Failed to wipe mappack score.')
    false
  end

  def compare_hashes
    # Prepare map data to hash
    map_data = highscoreable.dump_level(hash: true)
    return true if map_data.nil?
    to_hash = PWD + map_data[0xB8..-1]

    # Hash 1
    hash_c = sha1(to_hash, c: true)
    hash_ruby = sha1(to_hash, c: false)
    return false if !hash_c || !hash_ruby

    # Hash 2
    score = (1000.0 * score_hs.to_i / 60.0).round.to_s
    hash_c = sha1(hash_c + score, c: true)
    hash_ruby = sha1(hash_ruby + score, c: false)
    return false if !hash_c || !hash_ruby

    return hash_c == hash_ruby
  end

end

class MappackDemo < ActiveRecord::Base
  alias_attribute :score, :mappack_score
  belongs_to :mappack_score, foreign_key: :id

  # Delete orphaned demos (demos without a corresponding score)
  def self.sanitize
    orphans = joins('LEFT JOIN mappack_scores ON mappack_demos.id = mappack_scores.id')
                .where('mappack_scores.id IS NULL')
    count = orphans.count
    orphans.delete_all
    count
  end

  def decode
    Demo.decode(demo)
  end
end

# N++ sometimes submits individual level scores incorrectly when submitting
# episode runs. The fix required is to add the sum of the lengths of the
# runs for the previous levels in the episode, until we reach a level whose
# score was correct.

# Since all 5 level scores are not submitted in parallel, but in sequence, this
# table temporarily holds the adjustment, which will be updated and applied with
# each level, until all 5 are done, and then we delete it.
class MappackScoresTweak < ActiveRecord::Base
  alias_attribute :episode, :mappack_episode
  belongs_to :player
  belongs_to :mappack_episode, foreign_key: :episode_id

  # Returns the score if success, nil otherwise
  def self.tweak(score, player, level, header)
    # Not in episode, not tweaking
    return score if header[:type] != 1

    # Create or fetch tweak
    index = level.inner_id % 5
    if index == 0
      tw = self.find_or_create_by(player: player, episode: level.episode)
      tw.update(tweak: 0, index: 0) # Initialize tweak
    else
      tw = self.find_by(player: player, episode: level.episode)
      if tw.nil? # Tweak should exist
        warn("Tweak for #{player.name}'s #{level.episode.name} run should exit")
        return nil
      end
    end

    # Ensure tweak corresponds to the right level
    if tw.index != index
      warn("Tweak for #{player.name}'s #{level.episode.name} has index #{tw.index}, should be #{index}")
      return nil
    end

    # Tweak if necessary
    if header[:id] == level.inner_id # Tweak
      score += tw.tweak
      tw.tweak += header[:framecount] - 1
      tw.save
    else # Don't tweak, reset tweak for later
      tw.update(tweak: header[:framecount] - 1)
    end

    # Prepare tweak for next level
    index < 4 ? tw.update(index: index + 1) : tw.destroy

    # Tweaked succesfully
    return score
  rescue => e
    lex(e, 'Failed to tweak score')
    nil
  end
end

# A table to store all the calculated integrity hashes that do not match the
# submitted one. This could mean one of two things:
# 1) The score has been submitted with a different level, or has been cheated.
#    Either way, it needs to be checked.
# 2) Our SHA1 algo doesn't match the one used by N++, so we want to polish that.
#    This is currently happening sometimes (Edit: Not anymore)
class BadHash < ActiveRecord::Base
  # Remove orphaned bad hashes (missing corresponding mappack score)
  def self.sanitize
    orphans = joins('LEFT JOIN mappack_scores ON bad_hashes.id = mappack_scores.id')
                .where('mappack_scores.id IS NULL')
    count = orphans.count
    orphans.delete_all
    count
  end
end

# This table stores the Discord IDs for the channels that are dedicated to each
# mappack, so that decisions (such as default mappack for commands) can be based
# on this information
class MappackChannel < ActiveRecord::Base
  belongs_to :mappack
end

# This table stores all the precomputed SHA1 hashes for all versions of every
# mappack level, episode and story. This is used for replay integrity validation,
# and is actually what takes the most time.
class MappackHash < ActiveRecord::Base
  belongs_to :highscoreable, polymorphic: true

  # Update all hashes for all mappack highscoreables
  def self.seed(mappack: nil, types: [Level, Episode, Story])
    total = 0
    types.each{ |t| total += t.mappack.update_hashes(mappack: mappack, pre: true) }
    total
  end
end
