require 'time'

# Reformat date to timestamp rather than a string
# Add dates for last update of scores and map properties
class ImproveUserlevelDates < ActiveRecord::Migration[5.1]
  def change
    # For some STUPID reason, renaming timestamp columns doesn't work properly
    # So we have to use raw SQL, it's technical
    ActiveRecord::Base.connection.execute("ALTER TABLE `userlevels` CHANGE `last_update` `score_update` timestamp NULL DEFAULT NULL")
    rename_column :userlevels, :date,       :date_temp
    add_column    :userlevels, :date,       :timestamp, index: true
    add_column    :userlevels, :map_update, :timestamp, index: true
    add_index     :userlevels, :score_update

    count = Userlevel.count.to_i
    ActiveRecord::Base.transaction do
      Userlevel.all.each_with_index{ |u, i|
        print "Reformatting date #{i + 1} / #{count}...".ljust(80, ' ') + "\r"
        u.update(date: Time.strptime(u.date_temp, "%d/%m/%y %H:%M").strftime(DATE_FORMAT_MYSQL))
      }
    end
    puts ""

    remove_column :userlevels, :date_temp
  end
end
