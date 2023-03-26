# Remove archives, they don't make as much sense here since we have access to
# all submitted scores.
# Also, add speedrun fields, and rename hs ones accordingly.
class SimplifyMappacks < ActiveRecord::Migration[5.1]
  def change
    # Remove archives table
    drop_table :mappack_archives

    # Revamp scores table
    change_table :mappack_scores do |t|
      # Remove archive reference
      t.remove :archive_id

      # Rename hs fields explicitly
      t.rename :rank,      :rank_hs
      t.rename :tied_rank, :tied_rank_hs
      t.rename :score,     :score_hs

      # Change hs ranks to shorts (2 bytes)
      t.change :rank_hs,      :integer, index: true, limit: 2
      t.change :tied_rank_hs, :integer, index: true, limit: 2

      # Create sr fields
      t.integer :rank_sr,      limit: 2
      t.integer :tied_rank_sr, limit: 2
      t.integer :score_sr

      # Add sr indices (needs to be done separately, for some reason)
      t.index :rank_sr
      t.index :tied_rank_sr

      # Create archive-esque fields
      t.integer   :metanet_id
      t.timestamp :date
      
      # Add indices
      t.index :metanet_id
      t.index :date
    end
  end
end