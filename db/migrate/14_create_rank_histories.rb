class CreateRankHistories < ActiveRecord::Migration[5.1]
  def change
    create_table :rank_histories do |t|
      t.timestamp :timestamp, index: true

      t.string :tab, index: true
      t.string :highscoreable_type, index: true
      t.integer :rank, index: true
      t.boolean :ties

      t.references :player
      t.integer :metanet_id
      t.integer :count
    end

    create_table :points_histories do |t|
      t.timestamp :timestamp, index: true

      t.string :tab, index: true
      t.string :highscoreable_type, index: true

      t.references :player
      t.integer :metanet_id
      t.integer :points
    end

    create_table :total_score_histories do |t|
      t.timestamp :timestamp, index: true

      t.string :tab, index: true
      t.string :highscoreable_type, index: true

      t.references :player
      t.integer :metanet_id
      t.float :score
    end
  end
end
