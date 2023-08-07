class AddMappackVersions < ActiveRecord::Migration[5.1]
  def change
    add_column :mappacks, :version, :integer
    Mappack.update_all(version: 1)
  end
end