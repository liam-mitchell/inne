# Add fields to hold total gold count for each mappack highscoreable, so that
# it can be quickly compared against run's gold count to detect G++ runs
class AddGoldCounts < ActiveRecord::Migration[5.1]
  def change
    add_column :mappack_levels,   :gold, :integer, limit: 2
    add_column :mappack_episodes, :gold, :integer, limit: 2
    add_column :mappack_stories,  :gold, :integer, limit: 2
  end
end