class CreateNextScoreUpdate < ActiveRecord::Migration[5.1]
  def change
    # this is pretty greasy
    now = Time.now
    next_score_update = DateTime.new(now.year, now.month, now.day + 1, 0, 0, 0, now.zone)
    GlobalProperty.create(key: 'next_score_update', value: next_score_update.to_s)
  end
end
