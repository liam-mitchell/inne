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
    maps.each_with_index.map{ |m, i|
      log("Parsing map #{"%-3d" % (i + 1)} / #{count} from '#{fn}' for '#{pack}'...", newline: false)
      parse_metanet_map(m, i, File.basename(file), pack)
    }
    succ("Parsed Metanet map file '#{File.basename(file)}'", pad: true)
  rescue => e
    err("Error parsing Metanet map file '#{File.basename(file)}' for '#{pack}': #{e}")
  end
end

class Mappack < ActiveRecord::Base
  alias_attribute :levels, :mappack_levels
  alias_attribute :episodes, :mappack_episodes
  alias_attribute :stories, :mappack_stories
  has_many :mappack_levels
  has_many :mappack_episodes
  has_many :mappack_stories

  # TODO: Add botmaster command to execute this function
  # TODO: Add botmaster command to add remaining details to a mappack (title,
  #       authors, etc)
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

  def read
    dir = File.join(DIR_MAPPACKS, "#{id}_#{code}")
    if !Dir.exist?(dir)
      err("Directory for mappack '#{code}' not found, not reading")
      return
    end

    files = Dir.entries(dir).select{ |f|
      path = File.join(dir, f)
      File.file?(path) && File.extname(path) == ".txt"
    }
    warn("No appropriate files found in directory for mappack '#{code}'") if files.count == 0

    files.each{ |f|
      tab_code = f[0..-5]
      tab = TABS_NEW.find{ |tab, attr| attr[:files].key?(tab_code) }
      if tab.nil?
        warn("Unrecognized file '#{tab_code}' parsing mappack '#{code}'")
        next
      end
      Map.parse_metanet_file(File.join(dir, f), tab[1][:files][tab_code], code)
         .each_with_index{ |m, i|
        MappackLevel.find_or_create_by(id: TYPES[0][:slots] * id + i).update(
          inner_id:   i,
          mappack_id: id,
          mode:       tab[1][:mode],
          tab:        tab[0],
          episode_id: i / 5,
          name:       code.upcase + '-'
        )
      }
    }
  rescue
    err("Error reading mappack '#{code}'")
  end
end

class MappackData < ActiveRecord::Base

end

class MappackLevel < ActiveRecord::Base
  alias_attribute :scores, :mappack_scores
  alias_attribute :archives, :mappack_archives
  alias_attribute :episode, :mappack_episode
  has_many :mappack_scores, ->{ order(:rank) }, as: :highscoreable
  has_many :mappack_archives, as: :highscoreable
  belongs_to :mappack
  belongs_to :mappack_episode, foreign_key: :episode_id
  enum tab: TABS_NEW.map{ |k, v| [k, v[:mode] * 7 + v[:tab]] }.to_h
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
end

class MappackArchive < ActiveRecord::Base
  belongs_to :player
  belongs_to :highscoreable, polymorphic: true
  enum tab: TABS_NEW.map{ |k, v| [k, v[:mode] * 7 + v[:tab]] }.to_h
end

class MappackDemo < ActiveRecord::Base

end
