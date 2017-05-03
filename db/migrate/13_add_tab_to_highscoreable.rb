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

class AddTabToHighscoreable < ActiveRecord::Migration[5.1]
  def change
    add_column :levels, :tab, :integer, index: true
    add_column :episodes, :tab, :integer, index: true

    ActiveRecord::Base.transaction do
      Level.all.each { |l| l.update(tab: tab(l.name.split('-')[0])) }
      Episode.all.each { |e| e.update(tab: tab(e.name.split('-')[0])) }
    end
  end
end
