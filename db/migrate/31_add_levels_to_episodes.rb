class AddLevelsToEpisodes < ActiveRecord::Migration[5.1]
  def change
    change_table :levels do |t|
      t.references :episode
    end

    ActiveRecord::Base.transaction do
      Episode.all.each{ |e|
        print("Adding levels to episode #{e.name}...".ljust(80, " ") + "\r")
        Level.where("UPPER(name) LIKE ?", e.name.upcase + '%').each{ |l|
          l.update(episode: e)
        }
      }
    end
  end
end
