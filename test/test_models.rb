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
  test "scores update properly" do
    scores = [
      score('xela', 999),
      score('jp27ace', 999),
      score('High Priest o the Righteous Feed', 5)
    ]

    l = level(scores)

    assert l.scores.find_by(rank: 0).player.name == 'xela'
    assert l.scores.find_by(rank: 1).player.name == 'jp27ace'
    assert l.scores.find_by(rank: 2).player.name == 'High Priest o the Righteous Feed'
  end

  test "scores ignore hackers" do
    scores = [
      score('Kronogenics', 999999),
      score('fiordhraoi', 999999),
      score('BlueIsTrue', 999999),
      score('xela', 999)
    ]

    l = level(scores)

    assert_equal 'xela', l.scores.find_by(rank: 0).player.name
    assert_equal 0, l.scores.length
  end

  test "calculates spreads" do
    scores = [
      score('xela', 1000),
      score('jp27ace', 999),
      score('High Priest o the Righteous Feed', 900),
      score('Muzgrob', 800)
    ]

    l = level(scores)

    assert_score_equal 0.001, l.spread(1)
    assert_score_equal 0.100, l.spread(2)
    assert_score_equal 0.200, l.spread(3)
  end

  test "calculates diffs" do
    scores = [
      score('xela', 1000),
      score('jp27ace', 900),
      score('High Priest o the Righteous Feed', 800),
      score('Muzgrob', 700),
      score('natesly', 500)
    ]

    l = level(scores)

    old = l.scores.to_json(include: {player: {only: :name}})

    scores = [
      score('jp27ace', 1100),
      score('High Priest o the Righteous Feed', 1050),
      score('Muzgrob', 1010),
      score('TOAST BUSTERS', 1005),
      score('xela', 1000)
    ]

    l.expects(:get_scores).returns(scores)
    l.download_scores
    l.reload

    diff = l.difference(JSON.parse(old))

    assert_score_equal 0.2, diff[0][:change][:score]
    assert_equal 1, diff[0][:change][:rank]
    assert_equal 'jp27ace', diff[0][:score].player.name

    assert_score_equal 0.250, diff[1][:change][:score]
    assert_equal 1, diff[1][:change][:rank]
    assert_equal 'High Priest o the Righteous Feed', diff[1][:score].player.name

    assert_score_equal 0.310, diff[2][:change][:score]
    assert_equal 1, diff[2][:change][:rank]
    assert_equal 'Muzgrob', diff[2][:score].player.name

    assert_nil diff[3][:change]
    assert_equal 'TOAST BUSTERS', diff[3][:score].player.name

    assert_score_equal 0, diff[4][:change][:score]
    assert_equal -4, diff[4][:change][:rank]
    assert_equal 'xela', diff[4][:score].player.name
  end
end
