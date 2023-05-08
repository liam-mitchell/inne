# Read the corresponding class definition in the mappacks file to understand
# what tweaks are and why they're necessary.
class CreateMappackScoresTweaks < ActiveRecord::Migration[5.1]
  def change
    create_table :mappack_scores_tweaks do |t|
      t.integer :player_id,  index: true
      t.integer :episode_id, index: true
      t.integer :index
      t.integer :tweak
    end
  end
end
