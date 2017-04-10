class CreateGlobalProperties < ActiveRecord::Migration
  def change
    create_table :global_properties do |t|
      t.string :key, index: true
      t.string :value, index: true
    end
  end
end
