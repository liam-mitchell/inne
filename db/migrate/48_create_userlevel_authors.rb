# Substitute author field in userlevels with a reference to a table with all
# userlevel authors
# Also keep track of old names ("akas")
class CreateUserlevelAuthors < ActiveRecord::Migration[5.1]
  def change
    rename_column :userlevels, :author, :author_temp

    create_table :userlevel_authors do |t|
      t.string :name, index: true
    end

    create_table :userlevel_akas do |t|
      t.integer :author_id, index: true
      t.timestamp :date
      t.string :name
    end

    ActiveRecord::Base.transaction do
      count = Userlevel.count.to_i
      Userlevel.order(id: :asc).pluck(:author_id, :author_temp, :date).each_with_index{ |u, i|
        print("Creating userlevel author and aka for userlevel #{i + 1} / #{count}...".ljust(80, ' ') + "\r")
        date = Time.strptime(u[2], "%d/%m/%y %H:%M").strftime(DATE_FORMAT_MYSQL)
        UserlevelAuthor.where(id: u[0]).first_or_create(id: u[0]).rename(u[1], date)
      }
    end
    puts ""

    remove_column :userlevels, :author_temp
  end
end
