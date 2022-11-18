class AddFramecountToArchives < ActiveRecord::Migration[5.1]
  def change
    add_column :archives, :framecount, :integer
    add_column :archives, :gold, :integer
    total = Archive.count
    Archive.all.each_with_index{ |a, i|
      print("Adding framecount and gold #{i + 1} / #{total}...".ljust(80, ' ') + "\r")
      frames = Demo.find(a.id).framecount
      gold   = frames != -1 ? (((a.score + frames).to_f / 60 - 90) / 2).round : -1
      a.update(framecount: frames, gold: gold)
    }
  end
end
