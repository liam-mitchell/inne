# Move "expired" field from Demos to Archives, makes more sense
# Also delete "replay_id" and "htype" from Demos, the former is redundant and
# the second is useless.
class MoveExpired < ActiveRecord::Migration[5.1]
  def change
    add_column :archives, :lost, :boolean, index: true, default: false
    count = Demo.count
    [true, false].each{ |b|
      Archive.joins("INNER JOIN demos ON archives.id = demos.id")
             .where("demos.expired = #{b}")
             .update_all(lost: b)
    }
    puts ""
    change_table :demos do |t|
      t.remove :replay_id
      t.remove :expired
      t.remove :htype
    end
  end
end