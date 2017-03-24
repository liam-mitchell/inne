class AddScoresToPlayers < ActiveRecord::Migration
  def change
    change_table :scores do |t|
      t.references :player, index: true
      t.references :highscoreable, polymorphic: true, index: true
    end
  end
end
