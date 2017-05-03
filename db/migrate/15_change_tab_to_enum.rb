def tab(prefix)
  {
    'SI' => :SI,
    'S' => :S,
    'SL' => :SL,
    'SU' => :SU,
    '?' => :SS,
    '!' => :SS2
  }[prefix]
end

def change_table(type, table)
    add_column table, :newtab, :integer, index: true
    type.all.each { |h| h.update(newtab: tab(h.tab)) }

    change_column table, :tab, :integer, index: true
    type.all.each { |h| h.update(tab: h.newtab) }

    remove_column table, :newtab
end

class ChangeTabToEnum < ActiveRecord::Migration[5.1]
  def change
    change_table(TotalScoreHistory, :total_score_histories)
    change_table(PointsHistory, :points_histories)
    change_table(RankHistory, :rank_histories)
  end
end
