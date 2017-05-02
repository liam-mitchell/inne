class AddUserToPlayer < ActiveRecord::Migration[5.1]
  def change
    change_table :users do |t|
      t.references :player, index: true
    end
  end
end
