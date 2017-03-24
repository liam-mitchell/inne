class CreateScores < ActiveRecord::Migration
  def change
    create_table :scores do |t|
      t.integer :rank
      t.float :score
    end
  end
end
