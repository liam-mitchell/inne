class AddScoreIndexes < ActiveRecord::Migration[5.1]
  def change
    # Add the tab to the scores as well. This is redundant, but it makes
    # queries significantly simpler and more efficient compared to having
    # to query the corresponding highscoreables every time.
    add_column :scores, :tab, :integer, limit: 1
    total = Score.all.size
    Score.all.each_with_index{ |s, i|
      print("Updating tab for score #{i} / #{total}...".ljust(80, " ") + "\r")
      s.update(tab: s.highscoreable.tab)
    }

    # Add extra indexes to relevant columns to further enhance performance.
    add_index :scores, :tab
    add_index :scores, :tied_rank
    add_index :scores, :highscoreable_type
    add_index :scores, :highscoreable_id
  end
end
