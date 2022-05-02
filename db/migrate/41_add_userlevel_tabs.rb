# Position of userlevels in each of the userlevel tabs (best, featured,
# top weekly and hardest). Most will be NULL.
class AddUserlevelTabs < ActiveRecord::Migration[5.1]
  def change
    add_column :userlevels, :best,     :integer, default: nil
    add_column :userlevels, :featured, :integer, default: nil
    add_column :userlevels, :top,      :integer, default: nil
    add_column :userlevels, :hardest,  :integer, default: nil

    ['solo', 'coop', 'race'].each{ |m|
      folder = "maps/tabs/#{m}/"
      files = Dir.entries(folder).select{ |f| File.file?(folder + f) }
      files.each_with_index{ |f, i|
        print("Parsing #{m} file #{i + 1} of #{files.size}...".ljust(80, " ") + "\r")
        Userlevel::parse_tabs(File.binread(folder + f))
      }
    }

    GlobalProperty.find_or_create_by(key: 'next_userlevel_tab_update').update(value: Time.now.to_s)
  end
end