require 'csv'

def user(tag)
  {
    "ABA" => "ababab777",
    "AWE" => "Awein",
    "CAM" => "ibcamwhobu",
    "CHB" => "Chebyshevrolet",
    "EKI" => "ekisacik",
    "ES2" => "Alpha Espy's brother",
    "ESP" => "Alpha Espy",
    "FNY" => "Fnyt",
    "GEA" => "Geal",
    "GOL" => "golfkid",
    "HGB" => "HorribleGBlob",
    "HIT" => "Hitfreezy",
    "KOS" => "Kostucha",
    "MAE" => "Maelstrom",
    "MAQ" => "Maqrkk",
    "MOL" => "MoleTrooper",
    "NIM" => "Untamed Nim",
    "PBR" => "poober",
    "SCO" => "scottm",
    "SKY" => "Skylighter",
    "SUN" => "sunruibt",
    "SYS" => "systeminspired",
    "TST" => "Toaster",
    "WHA" => "Whamboss",
    "XEL" => "xela"
  }[tag]
end

def add_videos(tab, max_count)
  lines = CSV.read(tab + ".csv").drop(5)

  current_name = nil
  current_id = nil
  challenge = nil
  challenge_code = nil
  author = nil
  url = nil
 
  lines.each do |line|
    if line[1] =~ /[A-Z?!]-[A-Z]-[0-9][0-9](-[0-9][0-9])?/
      current_id = line[1]
      challenge = "G++"
    elsif line[1] =~ /([GTOCE][-+]+)+/
      challenge = line[1]
      challenge_code = line[4]
      challenge_code = challenge_code[1..challenge_code.length - 2] unless challenge_code.nil?
      challenge_code = "?!" if challenge_code.nil?
    else
      current_name = line[1]
      current_id = nil
      challenge = nil
      challenge_code = nil
      author = nil
      url = nil
      next
    end

    (5..(5 + max_count - 1)).each do |i|
      author_tag = line[i]
      next if author_tag.nil? || author_tag.empty?
      author_tag = author_tag[1..3]
      author = user(author_tag)
      url = line[i + max_count]

      highscoreable = Level.where(longname: current_name).first

      if highscoreable.nil?
        highscoreable = Episode.where(name: current_id).first
      end

      highscoreable.videos.create(
        author: author,
        author_tag: author_tag,
        challenge: challenge,
        challenge_code: challenge_code,
        url: url
      )
    end
  end
end

class CreateVideos < ActiveRecord::Migration[5.1]
  def change
    create_table :videos do |t|
      t.belongs_to :highscoreable, polymorphic: true
      t.string :author
      t.string :author_tag
      t.string :challenge
      t.string :challenge_code
      t.string :url
    end

    add_videos("L-S", 10)
    add_videos("L-SI", 8)
    add_videos("L-SU", 8)
    add_videos("L-SL", 8)
    add_videos("L-SS", 8)
    add_videos("L-SS2", 8)
    add_videos("E-S", 8)
    add_videos("E-SU", 8)
  end
end
