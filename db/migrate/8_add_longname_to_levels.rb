class AddLongnameToLevels < ActiveRecord::Migration
  def change
    change_table :levels do |t|
      t.string :longname
    end
  end
end
