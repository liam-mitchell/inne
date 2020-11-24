class AddArchiveIndexes < ActiveRecord::Migration[5.1]
  def change
    # Add the tab to the archives as well. This is redundant, but it makes
    # queries significantly simpler and more efficient compared to having
    # to query the corresponding highscoreables every time.
    add_column :archives, :tab, :integer, limit: 1
    total = Archive.all.size
    Archive.all.each_with_index{ |s, i|
      print("Updating tab for archive #{i} / #{total}...".ljust(80, " ") + "\r")
      s.update(tab: s.highscoreable.tab)
    }

    # Add extra indexes to relevant columns to further enhance performance.
    add_index :archives, :tab
    add_index :archives, :date
  end
end
