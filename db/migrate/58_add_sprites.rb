class AddSprites < ActiveRecord::Migration[5.1]
  def change
    create_table :sprites, id: false do |t|
      t.integer :palette_id, limit: 1, index: true
      t.integer :entity_id,  limit: 1
      t.boolean :object,     default: true
      t.boolean :special,    default: false
      t.binary  :image
    end
  end
end