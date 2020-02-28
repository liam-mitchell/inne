class CreateUserlevels < ActiveRecord::Migration[5.1]

  def change
    create_table :userlevels do |t|
      t.integer :author_id, index: true
      t.string :author
      t.string :title
      t.integer :favs
      t.string :date
      t.integer :mode

      t.binary :tile_data
      t.binary :object_data
    end

    # SOLO
    (0..96).each{ |l|
      levels = Userlevel::parse(File.binread("maps/solo/" + l.to_s), false)
      levels.each{ |map|
        Userlevel.create(
          id: map[:id],
          author_id: map[:author_id],
          author: map[:author],
          title: map[:title],
          favs: map[:favs],
          date: map[:date],
          mode: 0,
          tile_data: map[:tiles],
          object_data: map[:objects]
          # add reference to author (from the player table, find or create by name)
        )
        puts map[:id]
      }
    }

    # COOP
    (0..12).each{ |l|
      levels = Userlevel::parse(File.binread("maps/coop/" + l.to_s), false)
      levels.each{ |map|
        Userlevel.create(
          id: map[:id],
          author_id: map[:author_id],
          author: map[:author],
          title: map[:title],
          favs: map[:favs],
          date: map[:date],
          mode: 1,
          tile_data: map[:tiles],
          object_data: map[:objects]
          # add reference to author (from the player table, find or create by name)
        )
        puts map[:id]
      }
    }

    # RACE
    (0..8).each{ |l|
      levels = Userlevel::parse(File.binread("maps/race/" + l.to_s), false)
      levels.each{ |map|
        Userlevel.create(
          id: map[:id],
          author_id: map[:author_id],
          author: map[:author],
          title: map[:title],
          favs: map[:favs],
          date: map[:date],
          mode: 2,
          tile_data: map[:tiles],
          object_data: map[:objects]
          # add reference to author (from the player table, find or create by name)
        )
        puts map[:id]
      }
    }
  end

end
