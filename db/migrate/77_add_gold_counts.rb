class AddGoldCounts < ActiveRecord::Migration[5.1]
  def change
    add_column :mappack_levels,   :gold, :integer, limit: 2
    add_column :mappack_episodes, :gold, :integer, limit: 2
    add_column :mappack_stories,  :gold, :integer, limit: 2
  end
end