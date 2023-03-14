# TODO: This module should contain the functionality common to all maps:
#       Include it in Userlevels
module Map

end

class Mappack < ActiveRecord::Base
  alias_attribute :levels, :mappack_levels
  alias_attribute :episodes, :mappack_episodes
  alias_attribute :stories, :mappack_stories
  has_many :mappack_levels
  has_many :mappack_episodes
  has_many :mappack_stories

  def self.seed
    #Dir.entries(Dir.pwd)
    byebug
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
