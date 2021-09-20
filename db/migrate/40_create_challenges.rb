class CreateChallenges < ActiveRecord::Migration[5.1]
  def change
    create_table :challenges do |t|
      t.references :level, index: true
      t.integer    :index, limit: 1
      t.integer    :g    , limit: 1
      t.integer    :t    , limit: 1
      t.integer    :o    , limit: 1
      t.integer    :c    , limit: 1
      t.integer    :e    , limit: 1
    end

    [
      { filename: "Scodes.txt",   id:  600, total: 600 },
      { filename: "SScodes.txt",  id: 1800, total: 120 },
      { filename: "S2codes.txt",  id: 2400, total: 600 },
      { filename: "SS2codes.txt", id: 3000, total: 120 }
    ].each{ |f|
      File.read("db/challenges/" + f[:filename]).split("\n").each_with_index{ |l, i|
        print("Parsing #{f[:filename][0..-10]} tab: #{i} / #{f[:total]}...".ljust(80, " ") + "\r")
        l.split(" ").each_with_index{ |c, j|
          objs = { "G" => 0, "T" => 0, "O" => 0, "C" => 0, "E" => 0 }
          c.scan(/../).each{ |o|
            objs[o[1]] = o[0] == "A" ? 1 : (o[0] == "N" ? -1 : 2)
          }
          lvl = Level.find(f[:id] + i)
          Challenge.find_or_create_by(
            level: lvl,
            index: j,
            g:     objs["G"],
            t:     objs["T"],
            o:     objs["O"],
            c:     objs["C"],
            e:     objs["E"]
          )
        }
      } 
    }
  end
end
