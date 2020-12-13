class AddDisplayNames < ActiveRecord::Migration[5.1]
  def change
    add_column :users, :displayname, :string
  end
end
