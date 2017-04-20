def score(name, score)
  {'user_name' => name, 'score' => score}
end

def level(scores)
  l = Level.create
  l.expects(:get_scores).returns(scores)
  l.download_scores
  l.save
  l
end

def assert_score_equal(expected, actual)
  assert (expected - actual).abs < 0.001, "inequal scores: expected #{expected}, got #{actual}"
end

class TestScores < Test::Unit::TestCase
  def setup
    @scores = [
      create(:xela, rank: 0, score: 90.000),
      create(:jp, rank: 1, score: 89.000),
      create(:borlin, rank: 2, score: 88.000),
      create(:eddy, rank: 3, score: 87.000)
    ]

    @level = create(:level, scores: @scores)
  end

  test "scores update properly" do
    # scores = [
    #   score('xela', 999),
    #   score('jp27ace', 999),
    #   score('High Priest o the Righteous Feed', 5)
    # ]

    # l = level(scores)

    # assert l.scores.find_by(rank: 0).player.name == 'xela'
    # assert l.scores.find_by(rank: 1).player.name == 'jp27ace'
    # assert l.scores.find_by(rank: 2).player.name == 'High Priest o the Righteous Feed'
  end

  test "scores ignore hackers" do
    # scores = [
    #   score('Kronogenics', 999999),
    #   score('fiordhraoi', 999999),
    #   score('BlueIsTrue', 999999),
    #   score('xela', 999)
    # ]

    # l = level(scores)

    # assert_equal 'xela', l.scores.find_by(rank: 0).player.name
    # assert_equal 0, l.scores.length
  end

  test "calculates spreads" do
    assert_score_equal 1.000, @level.spread(1)
    assert_score_equal 2.000, @level.spread(2)
  end

  test "calculates diffs" do
    old = @level.scores.to_json(include: {player: {only: :name}})

    # Like above, with 4s improvement on Borlin (2nd -> 0th)
    # and 2s improvement on jp (still 1st), moving xela down (0th -> 2nd).
    # Also with a new score for golfkid between xela and jp.
    scores = [
      create(:borlin, rank: 0, score: 92.000),
      create(:jp, rank: 1, score: 91.000),
      create(:xela, rank: 2, score: 90.000),
      create(:golf, rank: 3, score: 89.000),
      create(:eddy, rank: 4, score: 87.000)
    ]

    current = create(:level, scores: scores)
    diff = current.difference(JSON.parse(old))

    assert_score_equal 4.000, diff[0][:change][:score]
    assert_equal 2, diff[0][:change][:rank]
    assert_equal 'Borlin', diff[0][:score].player.name

    assert_score_equal 2.000, diff[1][:change][:score]
    assert_equal 0, diff[1][:change][:rank]
    assert_equal 'jp27ace', diff[1][:score].player.name

    assert_score_equal 0.000, diff[2][:change][:score]
    assert_equal -2, diff[2][:change][:rank]
    assert_equal 'xela', diff[2][:score].player.name

    assert_nil diff[3][:change]
    assert_equal 'golfkid', diff[3][:score].player.name

    assert_score_equal 0.000, diff[4][:change][:score]
    assert_equal -1, diff[4][:change][:rank]
    assert_equal 'EddyMataGallos', diff[4][:score].player.name
  end
end

class TestRankings < Test::Unit::TestCase
  def setup
  end

  test "test one" do
    assert true
  end
end
