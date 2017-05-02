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

class CreateNextScoreUpdate < ActiveRecord::Migration[5.1]
  def change
    # this is pretty greasy
    now = Time.now
    next_score_update = DateTime.new(now.year, now.month, now.day + 1, 0, 0, 0, now.zone)
    GlobalProperty.create(key: 'next_score_update', value: next_score_update.to_s)
  end
end
