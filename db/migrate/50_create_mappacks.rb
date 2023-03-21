# First basic implementation of mappack support
class CreateMappacks < ActiveRecord::Migration[5.1]
  def change
    create_table :mappacks do |t|
      t.string    :name
      t.string    :code
      t.string    :authors
      t.timestamp :date
    end

    create_table :mappack_data do |t|
      t.binary :tile_data
      t.binary :object_data, limit: 1024 ** 2
    end

    create_table :mappack_levels do |t|
      t.integer :inner_id,   index: true, limit: 2
      t.integer :mappack_id, index: true, limit: 2
      t.integer :mode,       index: true, limit: 1
      t.integer :tab,        index: true, limit: 1
      t.integer :episode_id, index: true
      t.string  :name
      t.string  :longname,   index: true
    end

    create_table :mappack_episodes do |t|
      t.integer :inner_id,   index: true, limit: 2
      t.integer :mappack_id, index: true, limit: 2
      t.integer :mode,       index: true, limit: 1
      t.integer :tab,        index: true, limit: 1
      t.integer :story_id,   index: true
      t.string  :name
    end

    create_table :mappack_stories do |t|
      t.integer :inner_id,   index: true, limit: 2
      t.integer :mappack_id, index: true, limit: 2
      t.integer :mode,       index: true, limit: 1
      t.integer :tab,        index: true, limit: 1
      t.string  :name
    end

    create_table :mappack_scores do |t|
      t.integer :rank,               index: true, limit: 1
      t.integer :tied_rank,          index: true, limit: 1
      t.integer :tab,                index: true, limit: 1
      t.integer :player_id,          index: true
      t.integer :mappack_id,         index: true
      t.integer :highscoreable_id,   index: true
      t.string  :highscoreable_type, index: true
      t.integer :archive_id
      t.integer :score
    end

    create_table :mappack_archives do |t|
      t.integer   :player_id,          index: true
      t.integer   :metanet_id,         index: true
      t.integer   :highscoreable_id,   index: true
      t.string    :highscoreable_type, index: true
      t.timestamp :date,               index: true
      t.boolean   :expired,            index: true
      t.integer   :score
    end

    create_table :mappack_demos do |t|
      t.binary :demo
    end

    create_table :mappack_challenges do |t|
      t.integer :level_id, index: true
      t.integer :index,    limit: 1
      t.integer :g,        limit: 1
      t.integer :t,        limit: 1
      t.integer :o,        limit: 1
      t.integer :c,        limit: 1
      t.integer :e,        limit: 1
    end
  end
end