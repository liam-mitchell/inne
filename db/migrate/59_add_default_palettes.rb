class AddDefaultPalettes < ActiveRecord::Migration[5.1]
  def change
    add_column :users, :palette, :string
  end
end