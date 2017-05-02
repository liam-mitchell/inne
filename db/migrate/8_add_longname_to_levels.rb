class AddLongnameToLevels < ActiveRecord::Migration[5.1]
  def change
    change_table :levels do |t|
      t.string :longname
    end
  end
end
