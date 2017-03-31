class AddLongnameToLevels < ActiveRecord::Migration
  def get_names(file, starting_id)
    names = {}
    if File.exist?(file)
      File.open(file).read.each_line.each_with_index do |l, i|
        l = l.delete("\n")

        if !l.empty?
          names[i + starting_id] = {longname: l}
        end
      end
    end
    names
  end

  def change
    change_table :levels do |t|
      t.string :longname
    end

    names = get_names('names-SI.txt', 0).merge(get_names('names-S.txt', 600)).merge(get_names('names-SL.txt', 1200))
    ActiveRecord::Base.transaction do
      Level.update(names.keys, names.values)
    end
  end
end
