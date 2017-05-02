class CreateRankHistory < ActiveRecord::Migration[5.1]
  def change
    create_table :levels do |t|
      t.timestamp :timestamp, index: true
      t.integer :score_count
      t.integer :score_rank, index: true
      t.string :tab, index: true

      t.references :player
    end
  end
end
