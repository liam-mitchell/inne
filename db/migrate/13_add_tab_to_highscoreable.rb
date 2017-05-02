class AddTabToHighscoreable < ActiveRecord::Migration[5.1]
  def change
    add_column :levels, :tab, :string, index: true
    add_column :episodes, :tab, :string, index: true

    ActiveRecord::Base.transaction do
      Level.all.each { |l| l.update(tab: l.name.split('-')[0]) }
      Episode.all.each { |e| e.update(tab: e.name.split('-')[0]) }
    end
  end
end
