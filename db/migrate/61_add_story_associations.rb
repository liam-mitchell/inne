class AddStoryAssociations < ActiveRecord::Migration[5.1]
  def change
    add_column :episodes, :story_id, :integer

    Story.all.each{ |s|
      Episode.where('id DIV 5 = ?', s.id).update_all(story_id: s.id)
    }
  end
end