class FillHtypes < ActiveRecord::Migration[5.1]
  def change
    ActiveRecord::Base.transaction do
      count = Demo.all.size
      Demo.all.each_with_index{ |d, i|
        print("Updating demo #{i} / #{count}...".ljust(80, " ") + "\r")
        if d.htype.nil?
          d.update(htype: Demo.htypes[d.score.highscoreable_type.to_s.downcase])
        end
      }
    end
  end
end
