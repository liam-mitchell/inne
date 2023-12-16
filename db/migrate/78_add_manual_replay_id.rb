class AddManualReplayId < ActiveRecord::Migration[5.1]
  def change
    GlobalProperty.find_or_create_by(key: 'replay_id').update(value: nil)
  end
end