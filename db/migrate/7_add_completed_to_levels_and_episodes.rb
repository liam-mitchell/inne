class AddCompletedToLevelsAndEpisodes < ActiveRecord::Migration
  def change
    change_table :episodes do |t|
      t.boolean :completed
    end

    change_table :levels do |t|
      t.boolean :completed
    end
  end
end
