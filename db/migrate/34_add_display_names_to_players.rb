class AddDisplayNamesToPlayers < ActiveRecord::Migration[5.1]
  def change
    add_column :players, :display_name, :string
  end
end
