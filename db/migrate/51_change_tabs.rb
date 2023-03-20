# With this migration we do 2 things:
#   1) Reformat tab field to tinyint (1 byte)
#   2) Change tab indexes according to the formula the game uses:
#        7 * m + t (m = mode, t = tab)

def qstr(tab, type, field)
  "#{field} >= #{tab[:start] / 5 ** type} AND #{field} < #{(tab[:start] + tab[:size]) / 5 ** type}"
end

class ChangeTabs < ActiveRecord::Migration[5.1]
  def change
    # Reformat tab column to tinyint (1 byte)
    change_column :levels,   :tab, :integer, limit: 1
    change_column :episodes, :tab, :integer, limit: 1
    change_column :stories,  :tab, :integer, limit: 1

    # Change tab indexes
    TABS_NEW.each{ |k, v|
      tab = v[:mode] * 7 + v[:tab]
      types = [Level, Episode, Story]
      types.each_with_index{ |t, i|
        t.where(qstr(v, i, 'id')).update_all(tab: tab)
        [Score, Archive].each{ |c|
          c.where(highscoreable_type: t.to_s)
           .where(qstr(v, i, 'highscoreable_id')).update_all(tab: tab)
        }
      }
    }
  end
end