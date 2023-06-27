class UpdateLevelNames < ActiveRecord::Migration[5.1]
  def change
    count = Level.all.count
    changes = 0
    trivial = 0
    Level.all.each_with_index{ |l, i|
      print("Checking level #{"%3d" % [i + 1]} / #{count}...\r")
      old_name = l.longname
      new_name = l.map.longname
      if old_name != new_name
        old_name.strip == new_name.strip ? trivial += 1 : changes += 1
        l.update(longname: new_name)
      end
    }
    puts
    puts "Found #{changes + trivial} changes (#{changes} normal, #{trivial} trivial)."
  end
end