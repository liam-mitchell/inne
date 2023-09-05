# Add column to mappacks table that specifies whether there are lotds for that
# mappack
class AddMappackLotds < ActiveRecord::Migration[5.1]
  def change
    add_column :mappacks, :lotd, :boolean, default: false
    Mappack.where(code: ['met', 'ctp']).update_all(lotd: true)
  end
end