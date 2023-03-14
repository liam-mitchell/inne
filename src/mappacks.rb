# TODO: This module should contain the functionality common to all maps:
#       Include it in Userlevels
module Map
  # Parse a level in Metanet format (used by Metanet levels only)
  def self.parse_metanet_data(data)
    error = "Error parsing Metanet-format map"
    # Ensure format is "$map_name#map_data#", with map data being hex chars
    if data !~ /^\$(.*)\#(\h+)\#$/
      err("#{error}: Incorrect overall format.")
      return
    end
    title, map_data = $1, $2

    # Map data is dumped binary, so length must be even, and long enough to hold
    # header and tile data
    if !map_data.length % 2 == 0 || map_data.length / 2 < 4 + 966
      err("#{error}: Incorrect map data length (odd length, or too short).")
      return
    end

    # Map header missing
    if !map_data[0...8] == '00000000'
      err("#{error}: Header missing.")
      return
    end
    tiles = [map_data[8...1940]].pack('h*').bytes

    # Warning if invalid tiles
    invalid_count = tiles.count{ |t| t > 33 }
    if invalid_count > 0
      warn("Found #{invalid_count} invalid tiles parsing Metanet-format map")
    end

    # TODO: Finish parsing objects, add checks for tile IDs, unpaired doors/switches...
  end

  # TODO: Write method
  def self.parse_metanet_file

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
  def self.seed
    if !Dir.exist?(DIR_MAPPACKS)
      warn("Mappacks directory not found, not seeding")
      return
    end
    Dir.entries(DIR_MAPPACKS).select{ |d| !!d[/\d+_.+/] }.sort.each{ |d|
      id, code = d.split('_')
      if !Mappack.find_by(code: code)
        Mappack.create(id: id, code: code).read
      end
    }
  rescue
    err("Error seeding mappacks to database")
  end

  def read
    dir = File.join(DIR_MAPPACKS, "#{id}_#{code}")
    if !Dir.exist?(dir)
      warn("Directory for mappack '#{code}' not found, not reading")
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
      # TODO: Finish this, by calling Map.parse_metanet_file, and filling the db
    }
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
  enum tab: [:SI, :S, :SU, :SL, :SS, :SS2]
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
  enum tab: [:SI, :S, :SU, :SL, :SS, :SS2]
end

class MappackStory < ActiveRecord::Base
  alias_attribute :episodes, :mappack_episodes
  alias_attribute :scores, :mappack_scores
  alias_attribute :archives, :mappack_archives
  has_many :mappack_episodes, foreign_key: :story_id
  has_many :mappack_scores, ->{ order(:rank) }, as: :highscoreable
  has_many :mappack_archives, as: :highscoreable
  belongs_to :mappack
  enum tab: [:SI, :S, :SU, :SL, :SS, :SS2]
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
end

class MappackArchive < ActiveRecord::Base
  belongs_to :player
  belongs_to :highscoreable, polymorphic: true
end

class MappackDemo < ActiveRecord::Base

end
