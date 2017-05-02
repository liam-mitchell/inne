class CreateGlobalProperties < ActiveRecord::Migration[5.1]
  def change
    create_table :global_properties do |t|
      t.string :key, index: true
      t.string :value, index: true
    end
  end
end
