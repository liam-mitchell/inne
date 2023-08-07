# This file contains the generic Map module, that encapsulates a lot of the
# properties of an N++ map (map data format, screenshot generation, etc).
#
# Then, it includes all the classes related to mappacks (levels, episodes, stories,
# demos, etc), as well as the functions that handle the CLE server (Custom
# Leaderboard Engine).

#require 'chunky_png'
require 'oily_png'    # C wrapper for ChunkyPNG
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
  def self.encode_tiles(tiles)
    Zlib::Deflate.deflate(tiles.map{ |a| a.pack('C*') }.join, 9)
  end

  def self.encode_objects(objects)
    Zlib::Deflate.deflate(objects.transpose.map{ |a| a.pack('C*') }.join, 9)
  end

  def self.decode_tiles(tile_data)
    Zlib::Inflate.inflate(tile_data).bytes.each_slice(42).to_a
  end

  def self.decode_objects(object_data)
    dec = Zlib::Inflate.inflate(object_data)
    dec.bytes.each_slice((dec.size / 5).round).to_a.transpose
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
    tiles = tiles.each_slice(42).to_a

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
    lex(e, "Error parsing Metanet map file '#{fn}' for '#{pack}'")
    nil
  end

  def tiles
    Map.decode_tiles(data.tile_data)
  end

  def objects
    Map.decode_objects(data.object_data)
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

  def dump_tiles
    Zlib::Inflate.inflate(data.tile_data)
  end

  def dump_objects
    dec = Zlib::Inflate.inflate(data.object_data)
  end

  # This is used for computing the hash of a level. It's required due to a
  # misimplementation in N++, which instead of just hashing the map data,
  # overflows and copies object data from the next level before doing so.
  #
  # Returns false if we ran out of objects
  def complete_object_data(data, n)
    successor = next_h(tab: false)
    if successor == self
      return false
    else
      objs = successor.objects.take(n).map{ |o| o.pack('C5') }
      count = objs.count
      data << objs.join
      if count < n
        return successor.complete_object_data(data, n - count)
      else
        return true
      end
    end
  end

  # Generate a file with the usual userlevel format
  #   - query: The format for userlevel query files is used (shorter header)
  #   - hash:  Recursively fetches object data from next level to compute hash later
  def dump_level(query: false, hash: false)
    objs = self.objects
    # HEADER
    header = ""
    if !query
      header << _pack(0, 4)                    # Magic number
      header << _pack(1230 + 5 * objs.size, 4) # Filesize
    end
    mode = self.is_a?(MappackLevel) ? self.mode : Userlevel.modes[self.mode]
    author_id = query ? self.author_id : -1
    title = self.is_a?(MappackLevel) ? self.longname : self.title
    title = title[0..126].ljust(128, "\x00")
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
    tile_data = dump_tiles
    object_counts = [0] * 40
    objs.each{ |o| object_counts[o[0]] += 1 }
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
      coords:  []               # Coordinates of routes to trace
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
      tiles = maps.map{ |m| m.tiles.map(&:dup) }
      objects = maps.map{ |m|
        m.objects.reject{ |o| o[0] > 28 || o[0] == 8 } # Remove glitch objs and trap doors
         .sort_by{ |o| -OBJECTS[o[0]][:pref] }         # Sort objs by overlap preference
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
          image.compose!(obj, off_x + ppc * o[1] - obj.width / 2, off_y + ppc * o[2] - obj.height / 2)
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
        colors = n.times.map{ |i| PALETTE[OBJECTS[0][:pal] + n - 1 - i, palette_idx] }

        # Scale coordinates
        coords.each{ |c_list|
          c_list.each{ |coord|
            coord.map!{ |c| (ppu * c).round }
          }
        }
        
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
              colors[i],
              false,
              weight: 2,
              antialiasing: false
            ) if sizes[i] >= f + 2
          }
          image.save("frames/#{'%04d' % f}.png", :fast_rgb) if anim
        end
        bench(:step, 'Routes    ') if BENCH_IMAGES
      end
      

      # rb_p(rb_str_new_cstr("Hello, world!"));
      # rb_p(rb_sprintf("x0 = %ld", x0));
      if anim
        `ffmpeg -framerate 60 -pattern_type glob -i 'frames/*.png' 'frames/anim.mp4' > /dev/null 2>&1`
        res = File.binread('frames/anim.mp4')
        FileUtils.rm(Dir.glob('frames/*'))
      else
        res = image.to_blob(:fast_rgb)
      end
      bench(:step, 'Blobify   ') if BENCH_IMAGES
      res
    end

    bench(:step) if BENCHMARK

    file ? tmp_file(res, "#{h.name}.#{anim ? 'mp4' : 'png'}", binary: true) : res
  rescue => e
    lex(e, "Failed to generate screenshot")
    nil
  end

  def screenshot(theme = DEFAULT_PALETTE, file: false, blank: false, anim: false, coords: [])
    Map.screenshot(theme, file: file, blank: blank, anim: anim, coords: coords, h: self, ppc: anim ? 4 : 0)
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
        vert_x = [x + bx, x + bx, x + bx + c, x + dx - m - dm, x + dx -m, x + dx - m + dm, x + dx - bx - c, x + dx - bx, x + dx - bx]
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

  def trace(event)
    t = Time.now
    msg = event.content
    tmp_msg = [nil]
    h = parse_palette(event)
    msg, palette, error = h[:msg], h[:palette], h[:error]
    level = self.is_a?(MappackHighscoreable) && mappack.id == 0 ? Level.find_by(id: id) : self
    raise "Error finding level object" if level.nil?
    mappack = level.is_a?(MappackHighscoreable)
    userlevel = level.is_a?(Userlevel)
    board = parse_board(msg, 'hs')
    raise "Non-highscore modes (e.g. speedrun) are only available for mappacks" if !mappack && board != 'hs'
    raise "Traces are only available for either highscore or speedrun mode" if !['hs', 'sr'].include?(board)
    leaderboard = level.leaderboard(board, pluck: false)
    ranks = parse_ranks(msg, leaderboard.size).take(MAX_TRACES)
    scores = ranks.map{ |r| leaderboard[r] }.compact
    raise "No scores found for this level" if scores.empty?
    blank = !!msg[/\bblank\b/i]
    markers = { jump: false, left: false, right: false } if !!msg[/\bplain\b/i]
    markers = { jump: true,  left: true,  right: true  } if !!msg[/\binputs\b/i]
    markers = { jump: true,  left: false, right: false } if markers.nil?
    animate = !!msg[/\banimate\b/i]

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
    shell("python3 #{PATH_NTRACE}")

    # Read output files
    file = File.binread('output.txt') rescue nil
    raise "ntrace failed, please contact the botmaster for details." if file.nil?
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
    if animate
      trace = screenshot(palette, coords: coords, blank: blank, anim: true)
      raise 'Failed to generate screenshot' if trace.nil?
    else
      screenshot = screenshot(palette, file: true, blank: blank)
      raise 'Failed to generate screenshot' if screenshot.nil?
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
      raise 'Failed to trace replays' if trace.nil?
    end
    ext = animate ? 'mp4' : 'png'
    send_file(event, trace, "#{name}_#{ranks.map(&:to_s).join('-')}_trace.#{ext}", true)
    tmp_msg.first.delete rescue nil
    log("FINAL: #{"%8.3f" % [1000 * (Time.now - t)]}") if BENCH_IMAGES
  rescue RuntimeError => e
    if !tmp_msg.first.nil?
      tmp_msg.first.edit(e)
    else
      raise
    end
    event.drain
  rescue => e
    tmp_msg.first.edit('Failed to trace replays') if !tmp_msg.first.nil?
    event.drain
    lex(e, 'Failed to trace replays')
  end
end

class Mappack < ActiveRecord::Base
  alias_attribute :scores,   :mappack_scores
  alias_attribute :levels,   :mappack_levels
  alias_attribute :episodes, :mappack_episodes
  alias_attribute :stories,  :mappack_stories
  has_many :mappack_scores
  has_many :mappack_levels
  has_many :mappack_episodes
  has_many :mappack_stories
  enum tab: TABS_NEW.map{ |k, v| [k, v[:mode] * 7 + v[:tab]] }.to_h

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
  rescue => e
    lex(e, "Error seeding mappacks to database")
  end

  # TODO: Parse challenge files, in a separate function with its own command,
  # which is also called from the general seed and read functions.

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
      mappack_offset = TYPES['Level'][:slots] * id
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
  rescue => e
    lex(e, "Error reading mappack '#{code}'")
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

  # Set the mappack's name and author on command, since that's not parsed from the files
  def set_info(name, author, date)
    self.update(
      name:    name,
      authors: author,
      date:    Time.strptime(date, '%Y/%m/%d').strftime(DATE_FORMAT_MYSQL)
    )
  rescue => e
    lex(e, "Failed to set mappack '#{code}' info")
    nil
  end
end

class MappackData < ActiveRecord::Base
  alias_attribute :level, :mappack_level
  belongs_to :mappack_level, foreign_key: :id
end

module MappackHighscoreable
  include Highscoreable

  def type
    self.class.to_s
  end

  # Return leaderboards, filtering obsolete scores and sorting appropiately
  # depending on the mode (hs / sr).
  # Optionally sort by score and date instead of rank (used for computing the rank)
  def leaderboard(m = 'hs', score = false, truncate: 20, pluck: true, aliases: false)
    m = 'hs' if !['hs', 'sr', 'gm'].include?(m)
    names = aliases ? 'IF(display_name IS NOT NULL, display_name, name)' : 'name'
    attr_names = %W[id score_#{m} name metanet_id]

    # Handle standard boards
    if ['hs', 'sr'].include?(m)
      attrs = %W[mappack_scores.id score_#{m} #{names} metanet_id]
      board = scores.where("rank_#{m} IS NOT NULL")
      if score
        board = board.order("score_#{m} #{m == 'hs' ? 'DESC' : 'ASC'}, date ASC")
      else
        board = board.order("rank_#{m} ASC")
      end
    end

    # Handle gold boards
    if m == 'gm'
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

    # Truncate, fetch player names, and convert to hash
    board = board.limit(truncate) if truncate > 0
    return board if !pluck
    board.joins("INNER JOIN players ON players.id = player_id")
         .pluck(*attrs).map{ |s| attr_names.zip(s).to_h }
  end

  # Return scores in JSON format expected by N++
  def get_scores(qt = 0, metanet_id = nil)
    # Determine leaderboard type
    m = qt == 2 ? 'sr' : 'hs'

    # Fetch scores
    board = leaderboard(m)

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
        "rank"      => i,
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
  end

  # Verifies the integrity of a replay by generating the security hash and
  # comparing it with the submitted one.
  # This hash depends on both the score and the map data, so a score cannot
  # be submitted if the map is changed.
  def verify_replay(ninja_check, score)
    score = (1000.0 * score / 60.0).round.to_s
    h = hash
    h.nil? ? true : Digest::SHA1.digest(h + score) == ninja_check
  end
end

class MappackLevel < ActiveRecord::Base
  include Map
  include MappackHighscoreable
  include Levelish
  alias_attribute :data, :mappack_data
  alias_attribute :scores, :mappack_scores
  alias_attribute :episode, :mappack_episode
  has_one :mappack_data, foreign_key: :id
  has_many :mappack_scores, as: :highscoreable
  belongs_to :mappack
  belongs_to :mappack_episode, foreign_key: :episode_id
  enum tab: TABS_NEW.map{ |k, v| [k, v[:mode] * 7 + v[:tab]] }.to_h

  # Computes the level's hash, which the game uses for integrity verifications
  def hash
    map_data = dump_level(hash: true)
    map_data.nil? ? nil : Digest::SHA1.digest(PWD + map_data[0xB8..-1])
  end

  # Dump demo header for communications with N++
  def demo_header(framecount)
    # Precompute some values
    n = mode == 1 ? 2 : 1
    framecount /= n
    size = framecount * n + 26 + 4 * n

    # Build header
    header = [0].pack('C')                  # Type (0 lvl, 1 lvl in ep, 2 lvl in sty)
    header << [size].pack('L<')             # Data length
    header << [1].pack('L<')                # Replay version
    header << [framecount].pack('L<')       # Data size in bytes
    header << [inner_id].pack('L<')         # Level ID
    header << [mode].pack('L<')             # Mode (0-2)
    header << [0].pack('L<')                # ?
    header << (mode == 1 ? "\x03" : "\x01") # Ninja mask (1,3)
    header << [-1, -1].pack("l<#{n}")   # ?

    # Return
    header
  end
end

class MappackEpisode < ActiveRecord::Base
  include MappackHighscoreable
  include Episodish
  alias_attribute :levels, :mappack_levels
  alias_attribute :scores, :mappack_scores
  alias_attribute :story, :mappack_story
  alias_attribute :tweaks, :mappack_scores_tweaks
  has_many :mappack_levels, foreign_key: :episode_id
  has_many :mappack_scores, as: :highscoreable
  has_many :mappack_scores_tweaks, foreign_key: :episode_id
  belongs_to :mappack
  belongs_to :mappack_story, foreign_key: :story_id
  enum tab: TABS_NEW.map{ |k, v| [k, v[:mode] * 7 + v[:tab]] }.to_h

  # Computes the episode's hash, which the game uses for integrity verifications
  def hash
    hashes = levels.order(:id).map(&:hash).compact
    hashes.size < 5 ? nil : hashes.join
  end

  # Header of an episode demo:
  #   4B - Magic number (0xffc0038e)
  #  20B - Block length for each level demo (5 * 4B)
  def demo_header(framecounts)
    header_size = 26 + 4 * (mode == 1 ? 2 : 1)
    replay = [MAGIC_EPISODE_VALUE].pack('L<')
    replay << framecounts.map{ |f| f + header_size }.pack('L<5')
  end
end

class MappackStory < ActiveRecord::Base
  include MappackHighscoreable
  include Storyish
  alias_attribute :episodes, :mappack_episodes
  alias_attribute :scores, :mappack_scores
  has_many :mappack_episodes, foreign_key: :story_id
  has_many :mappack_scores, as: :highscoreable
  belongs_to :mappack
  enum tab: TABS_NEW.map{ |k, v| [k, v[:mode] * 7 + v[:tab]] }.to_h

  # Computes the story's hash, which the game uses for integrity verifications
  def hash
    hashes = episodes.map{ |e| e.levels.map(&:hash) }.flatten.compact
    return nil if hashes.size < 25
    work = 0.chr * 20
    25.times.each{ |i|
      work = Digest::SHA1.digest(work + hashes[i])
    }
    work
  end

  # Header of a story demo:
  #   4B - Magic number (0xff3800ce)
  #   4B - Demo data block total size
  # 100B - Block length for each level demo (25 * 4B)
  def demo_header(framecounts)
    header_size = 26 + 4 * (mode == 1 ? 2 : 1)
    replay = [MAGIC_STORY_VALUE].pack('L<')
    replay << [framecounts.sum + 25 * header_size].pack('L<')
    replay << framecounts.map{ |f| f + header_size }.pack('L<25')
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
  # TODO: Implement HC stories

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
      _thread do
        klass = sid >= MIN_ID ? Userlevel : type[:name].constantize
        klass.find_by(id: sid).update_scores(fast: true)
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
      #res['better'] = 1
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
      if !MappackScore.verify_gold(goldf) && type[:name] != 'Story'
        str = "Potentially incorrect hs score submitted by #{name} in #{h.name} (ID #{score.id})"
        warn(str, discord: true)
      end

      # Warn if the score submitted failed the map data integrity checks
      warn("Score submitted by #{name} to #{h.name} has invalid security hash", discord: true) if !legit
    end

    # Update ranks if necessary
    h.update_ranks('hs') if hs
    h.update_ranks('sr') if sr

    # Delete redundant scores of the player in the highscoreable
    # We delete all the scores that aren't keepies (were never a hs/sr PB),
    # and which no longer have the max/min amount of gold collected.
    pb_hs = nil # Highscore PB
    pb_sr = nil # Speedrun PB
    keepies = []
    scores.order(:id).each{ |s|
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
    scores.where(rank_hs: nil, rank_sr: nil)
          .where("gold < #{gold_max} AND gold > #{gold_min}")
          .where.not(id: keepies)
          .each(&:wipe)

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
      warn("Getting scores: #{type[:name]} ID:#{sid} for mappack '#{code}' not found")
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

  def self.patch_score(id, highscoreable, player, score)
    # Find score
    if !id.nil? # If ID has been provided
      s = MappackScore.find_by(id: id)
      raise "Mappack score of ID #{id} not found" if score.nil?
      highscoreable = s.highscoreable
      player = s.player
      scores = MappackScore.where(highscoreable: highscoreable, player: player)
      raise "#{player.name} does not have a score in #{highscoreable.name}" if scores.empty?
    else # If highscoreable and player have been provided
      raise "#{highscoreable.name} does not belong to a mappack" if !highscoreable.is_a?(MappackHighscoreable)
      scores = self.where(highscoreable: highscoreable, player: player)
      raise "#{player.name} does not have a score in #{highscoreable.name}" if scores.empty?
      s = scores.where.not(rank_hs: nil).first
      raise "#{player.name}'s leaderboard score in #{highscoreable.name} not found" if s.nil?
    end

    # Score integrity checks
    new_score = (score * 60).round
    gold = MappackScore.gold_count(highscoreable.type, new_score, s.score_sr)
    raise "That score is incompatible with the framecount" if !MappackScore.verify_gold(gold) && type[:name] != 'Story'

    # Change score
    old_score = s.score_hs.to_f / 60.0
    s.update(score_hs: new_score, gold: gold.round)

    # Update player's ranks
    scores.update_all(rank_hs: nil, tied_rank_hs: nil)
    max = scores.find_by(score_hs: scores.pluck(:score_hs).max)
    max.update(rank_hs: -1, tied_rank_hs: -1)

    # Update global ranks
    highscoreable.update_ranks('hs')
    succ("Patched #{player.name}'s score (#{s.id}) in #{highscoreable.name} from #{"%.3f" % old_score} to #{"%.3f" % score}")
  rescue => e
    lex(e, 'Failed to patch score')
    nil
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
  def self.gold_check
    scores = []
    entries = self.where("highscoreable_type != 'MappackStory' and id > #{MIN_REPLAY_ID}")
    count = entries.size

    entries.each_with_index{ |s, i|
      dbg("Checking gold in mappack score #{i + 1} / #{count}...", newline: false, pad: true)
      scores << s if !s.verify_gold
    }

    scores.sort_by{ |s| [s.highscoreable_type, s.highscoreable_id, s.player.name] }
  end

  def gold_count
    self.class.gold_count(highscoreable.type, score_hs, score_sr)
  end

  def verify_gold
    self.class.verify_gold(gold_count)
  end

  # Dumps demo data in the format N++ users for server communications
  def dump_demo
    h = highscoreable
    type = TYPES[h.class.to_s.remove('Mappack')]
    demos = Demo.decode(demo.demo, true)

    case type[:name]
    when 'Level'
      replay = highscoreable.demo_header(demos[0].size) + demos[0]
    when 'Episode'
      replay = highscoreable.demo_header(demos.map(&:size))
      highscoreable.levels.each_with_index.map{ |l, i|
        replay << l.demo_header(demos[i].size)
        replay << demos[i]
      }
    when 'Story'
      replay = highscoreable.demo_header(demos.map(&:size))
      highscoreable.episodes.each_with_index{ |e, j|
        e.levels.each_with_index{ |l, i|
          replay << l.demo_header(demos[5 * j + i].size)
          replay << demos[5 * j + i]
        }
      }
    else
      raise
    end
    
    replay
  rescue => e
    lex(e, "Failed to dump demo with ID #{id}")
    return
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

  def wipe
    demo.destroy
    self.destroy
  end

end

class MappackDemo < ActiveRecord::Base
  alias_attribute :score, :mappack_score
  belongs_to :mappack_score, foreign_key: :id
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
      return nil if tw.nil? # Tweak should exist
    end

    # Ensure tweak corresponds to the right level
    return nil if tw.index != index

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
  rescue
    nil
  end
end
