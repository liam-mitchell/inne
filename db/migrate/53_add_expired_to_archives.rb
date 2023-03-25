class AddExpiredToArchives < ActiveRecord::Migration[5.1]
  def change
    add_column :archives, :expired, :boolean, index: true, default: false
    count = Archive.count
    Archive.order(id: :asc).each_with_index{ |ar, i|
      print("Calculating expiration for archive #{i + 1} / #{count}...".ljust(80, ' ') + "\r")
      Archive.where(highscoreable: ar.highscoreable, player: ar.player)
             .where("id < ?", ar.id)
             .update_all(expired: true)
    }
    puts ''
  end
end