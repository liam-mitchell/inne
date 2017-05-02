class AddCompletedToLevelsAndEpisodes < ActiveRecord::Migration[5.1]
  def change
    change_table :episodes do |t|
      t.boolean :completed
    end

    change_table :levels do |t|
      t.boolean :completed
    end
  end
end
