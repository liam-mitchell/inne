# Add field to hold completion count for each highscoreable
class AddCompletions < ActiveRecord::Migration[5.1]
  def change
    add_column :levels,           :completions, :integer, index: true
    add_column :episodes,         :completions, :integer, index: true
    add_column :stories,          :completions, :integer, index: true
    add_column :mappack_levels,   :completions, :integer, index: true
    add_column :mappack_episodes, :completions, :integer, index: true
    add_column :mappack_stories,  :completions, :integer, index: true
    add_column :userlevels,       :completions, :integer, index: true
  end
end