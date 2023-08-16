# Create a table to store incorrectly computed SHA1 hashes, so that we can hopefully
# figure out a pattern
class CreateBadHashes < ActiveRecord::Migration[5.1]
  def change
    create_table :bad_hashes, id: false do |t|
      t.integer :score_id, index: true
      t.integer :score
      t.string :npp_hash
    end
  end
end