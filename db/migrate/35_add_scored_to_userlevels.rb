class AddScoredToUserlevels < ActiveRecord::Migration[5.1]
  def change
    add_column :userlevels, :scored, :boolean

    ids = UserlevelScore.distinct.pluck(:userlevel_id)
    Userlevel.where(id: ids).update_all(scored: true)
  end
end
