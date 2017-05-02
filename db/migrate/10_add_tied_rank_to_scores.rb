class AddTiedRankToScores < ActiveRecord::Migration[5.1]
  def change
    change_table :scores do |t|
      t.integer :tied_rank, index: true
    end

    add_index(:scores, :rank)

    Score.all.each do |s|
      s.tied_rank = s.highscoreable.scores.where(score: s.score).pluck(:rank).min
      s.save!
    end
  end
end
