# Create a dedicated table to store the precomputed SHA1 hashes for all
# mappack levels, episodes and stories, and for all their versions.
# This is what actually takes the most time during integrity checks, so we
# can save a lot with this approach.
class AddMappackHashes < ActiveRecord::Migration[5.1]
  def change
    create_table :mappack_hashes do |t|
      t.integer :highscoreable_id,   index: true
      t.string  :highscoreable_type, index: true
      t.integer :version,   limit: 1
      t.binary  :sha1_hash, limit: 100
    end
  end
end