class AddUserToPlayer < ActiveRecord::Migration
  def change
    change_table :users do |t|
      t.references :player, index: true
    end
  end
end
