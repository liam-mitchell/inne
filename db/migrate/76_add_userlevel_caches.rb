# Userlevel query cache
#   key:    SHA1 hash of the string formed by concatenating the userlevel IDs in this query
#   result: Resulting map collection, ready to be sent to N++
#   date:   Timestamp, so that we can delete expired query results
class AddUserlevelCaches < ActiveRecord::Migration[5.1]
  def change
    create_table :userlevel_caches do |t|
      t.string    :key
      t.binary    :result
      t.timestamp :date
    end

    add_column :users, :query, :integer, index: true
  end
end