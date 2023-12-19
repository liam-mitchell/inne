class AddUserlevelSubmitted < ActiveRecord::Migration[5.1]
  def change
    add_column :userlevels, :submitted,   :boolean, index: true
  end
end
