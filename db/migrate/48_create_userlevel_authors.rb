class CreateUserlevelAuthors < ActiveRecord::Migration[5.1]
  def change
    create_table :userlevel_authors do |t|
      t.string :name, index: true
    end

    create_table :userlevel_akas do |t|
      t.integer :author_id, index: true
      t.integer :userlevel_id
      t.string :name
    end

    ActiveRecord::Base.transaction do
      count = Userlevel.count.to_i
      Userlevel.order(id: :desc).pluck(:author_id, :author, :id).each_with_index{ |u, i|
        print("Creating userlevel author and aka for userlevel #{i} / #{count}...".ljust(80, ' ') + "\r")
        UserlevelAuthor.where(id: u[0]).first_or_create(id: u[0], name: u[1])
        UserlevelAka.where(author_id: u[0], name: u[1]).first_or_create(author_id: u[0], name: u[1], userlevel_id: u[2])
      }
    end
  end
end
