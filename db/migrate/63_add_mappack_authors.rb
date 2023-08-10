class AddMappackAuthors < ActiveRecord::Migration[5.1]
  def change
    add_column :mappack_levels, :author, :string
    Mappack.find_by(code: 'ctp').read_authors 
  end
end