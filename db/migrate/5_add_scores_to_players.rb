class AddScoresToPlayers < ActiveRecord::Migration[5.1]
  def change
    change_table :scores do |t|
      t.references :player, index: true
      t.references :highscoreable, polymorphic: true, index: false
    end
  end
end
