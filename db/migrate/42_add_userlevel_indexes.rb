class AddUserlevelIndexes < ActiveRecord::Migration[5.1]
  def change
    # Add extra indexes to relevant columns to further enhance performance.
    # Mainly required for smooth userlevel browsing.
    ## We add one column (tab) whose only purpose is to summarize the info
    ## of 4 others, in a way that it suffices to index just this one column
    ## instead of the other 4 and we still get the benfits.
    # Other important notes:
    # * Indexes are composite so that we can filter by some columns and sort
    #   by others, without losing the benefit of the index.
    # * In composite indexes the order does matter, that's why the indexes
    #   below are not redundant. For our needs, we will want to sort by
    #   one field and possibly filter by several others. In this case,
    #   the field we sort by should be the first in the composite index,
    #   and the fields we filter by (in a where clause) come afterwards.
    #   The order of the latter does not matter, since the where clause
    #   is commutative (thankfully, otherwise we would've required more
    #   index combinations).
    # * One exception is the ID, which due to being the primary key of the
    #   table, is a clustered index, and thus we always get the additional
    #   performance without needing to compose it with other indices.
=begin
    add_column :userlevels, :tab, :string
    count = Userlevel.count.to_i
    ActiveRecord::Base.transaction do
      Userlevel.all.each_with_index{ |u, i|
        print("Generating tab for userlevel #{i} / #{count}...".ljust(80, " ") + "\r")
        tab = ""
        tab += "h" if !u[:hardest].nil?
        tab += "f" if !u[:featured].nil?
        tab += "b" if !u[:best].nil?
        tab += "t" if !u[:top].nil?
        u.update(tab: tab)
      }
    end
=end
    add_index :userlevels, [:title,  :author, :mode]
    add_index :userlevels, [:author, :title,  :mode]
    add_index :userlevels, [:favs,   :title,  :mode, :author]
  end
end
