# Create a table to store incorrectly computed SHA1 hashes, so that we can hopefully
# figure out a pattern
class CreateBadHashes < ActiveRecord::Migration[5.1]
  def change
    create_table :bad_hashes do |t|
      t.integer :score
      t.binary  :npp_hash, limit: 20
    end
  end
end