class CreateRoles < ActiveRecord::Migration[5.1]
  def change
    add_column :users, :discord_id, :integer, limit: 8
    create_table :roles do |t|
      t.integer :discord_id, limit: 8
      t.string  :role
    end
  end
end