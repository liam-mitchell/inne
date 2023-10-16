class AddMappackDataVersions < ActiveRecord::Migration[5.1]
  def change
    add_column :mappack_data, :highscoreable_id, :integer, index: true
    add_column :mappack_data, :version, :integer
    MappackData.delete_all
  end
end