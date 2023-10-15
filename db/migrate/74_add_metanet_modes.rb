# Add playing mode (Solo, Coop, Race) to Metanet highscoreables, so that:
# - We can define certain methods, that depend on the mode, for all Highscoreables
# - Future-proof the db, in case we ever implement the other modes
class AddMetanetModes < ActiveRecord::Migration[5.1]
  def change
    add_column :levels,   :mode, :integer, index: true
    add_column :episodes, :mode, :integer, index: true
    add_column :stories,  :mode, :integer, index: true

    Level.update_all(mode: 0)
    Episode.update_all(mode: 0)
    Story.update_all(mode: 0)
  end
end