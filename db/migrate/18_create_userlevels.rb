class CreateUserlevels < ActiveRecord::Migration[5.1]

  def change
    create_table :userlevels do |t|
      t.integer :author_id, index: true
      t.string :author
      t.string :title
      t.integer :favs
      t.string :date
      t.integer :mode
    end

    create_table :userlevel_data do |t|
      # We limit object data to 1MB to force MySQL to create a MEDIUMBLOB,
      # which can hold up to 16MB, otherwise a BLOB is created, which can only
      # hold 64KB and is thus not sufficient for the theoretical biggest
      # possible maps.
      t.binary :tile_data
      t.binary :object_data, limit: 1024 ** 2
    end

    ['solo', 'coop', 'race'].each_with_index{ |mode, i|
      folder = "maps/#{mode}/"
      # We select all files which name is a number (possibly with padding 0s)
      files = Dir.entries(folder).select{ |f| File.file?(folder + f) && (f.to_i.to_s == f[/[^0].*/] || f.tr("0","").empty?) }.sort
      files.each_with_index{ |f, i|
        print("Parsing #{mode} page #{i} of #{files.size}.".ljust(80, " ") + "\r")
        levels = Userlevel::parse(File.binread(folder + f), true)
      }
    }
  end

end
