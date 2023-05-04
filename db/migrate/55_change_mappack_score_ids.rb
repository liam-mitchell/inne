class ChangeMappackScoreIds < ActiveRecord::Migration[5.1]
  def change
    MappackScore.order(id: :desc).update_all("id = id + #{MIN_REPLAY_ID}")
    MappackDemo.order(id: :desc).update_all("id = id + #{MIN_REPLAY_ID}")
    MappackScore.find_or_create_by(id: MIN_REPLAY_ID)
  end
end
