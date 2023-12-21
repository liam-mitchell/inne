# Add configurable replay ID field so that the botmaster can send specific runs
# to the leaderboards via CLE. This is useful for when a run is not in the
# leaderboards, perhaps it's even obsolete, but we want to watch it somehow.
class AddManualReplayId < ActiveRecord::Migration[5.1]
  def change
    GlobalProperty.find_or_create_by(key: 'replay_id').update(value: nil)
  end
end