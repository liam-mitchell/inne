require 'byebug'

def assert_score_equal(expected, actual)
  assert (expected - actual).abs < 0.001, "inequal scores: expected #{expected}, got #{actual}"
end

class TestScores < Test::Unit::TestCase
  def setup
    DatabaseCleaner.start

    @scores = [
      create(:xela, rank: 0, score: 90.000),
      create(:jp, rank: 1, score: 89.000),
      create(:borlin, rank: 2, score: 88.000),
      create(:eddy, rank: 3, score: 87.000)
    ]

    @level = create(:level, scores: @scores)
  end

  def teardown; DatabaseCleaner.clean; end

  test "scores ignore hackers" do
    scores = [
      {'user_name' => 'Kronogenics', 'score' => 999999},
      {'user_name' => 'BlueIsTrue', 'score' => 999999},
      {'user_name' => 'fiordhraoi', 'score' => 999999},
      {'user_name' => 'xela', 'score' => 90000}
    ]

    @level.stubs(:get_scores).returns(scores)
    @level.download_scores

    assert_equal 'xela', @level.scores.find_by(rank: 0).player.name
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
    DatabaseCleaner.start

    borlin = create(:player, name: 'Borlin')
    xela = create(:player, name: 'xela')
    jp = create(:player, name: 'jp27ace')
    eddy = create(:player, name: 'EddyMataGallos')

    @levels = 4.times.map { |i| create(:level) }

    scores = [
      [
        create(:score, highscoreable: @levels[0], player: borlin, rank: 0, score: 90.000),
        create(:score, highscoreable: @levels[0], player: jp, rank: 1, score: 89.000),
        create(:score, highscoreable: @levels[0], player: xela, rank: 2, score: 88.000)
      ],
      [
        create(:score, highscoreable: @levels[1], player: borlin, rank: 0, score: 90.000),
        create(:score, highscoreable: @levels[1], player: xela, rank: 1, score: 89.000),
        create(:score, highscoreable: @levels[1], player: jp, rank: 2, score: 88.000)
      ],
      [
        create(:score, highscoreable: @levels[2], player: borlin, rank: 0, score: 90.000),
        create(:score, highscoreable: @levels[2], player: xela, rank: 1, score: 90.000, tied_rank: 0),
        create(:score, highscoreable: @levels[2], player: jp, rank: 2, score: 87.000)
      ],
      [
        create(:score, highscoreable: @levels[3], player: eddy, rank: 0, score: 90.000),
        create(:score, highscoreable: @levels[3], player: xela, rank: 1, score: 90.000, tied_rank: 0),
        create(:score, highscoreable: @levels[3], player: jp, rank: 2, score: 87.000)
      ]
    ]
  end

  def teardown; DatabaseCleaner.clean; end

  test "0th rankings" do
    rankings = Player.rankings { |p| p.top_n_count(1, Level, false) }

    assert_equal 'Borlin', rankings[0][0].name
    assert_equal 3, rankings[0][1]

    assert_equal 'EddyMataGallos', rankings[1][0].name
    assert_equal 1, rankings[1][1]
  end

  test "tied rankings" do
    rankings = Player.rankings { |p| p.top_n_count(1, Level, true) }

    assert_equal 'Borlin', rankings[0][0].name
    assert_equal 3, rankings[0][1]

    assert_equal 'xela', rankings[1][0].name
    assert_equal 2, rankings[1][1]
  end

  test "point rankings" do
    rankings = Player.rankings { |p| p.points }

    assert_equal 'xela', rankings[0][0].name
    assert_equal 75, rankings[0][1]

    assert_equal 'jp27ace', rankings[1][0].name
    assert_equal 73, rankings[1][1]
  end

  test "score rankings" do
    rankings = Player.rankings { |p| p.total_score }

    assert_equal 'xela', rankings[0][0].name
    assert_score_equal 357.0, rankings[0][1]

    assert_equal 'jp27ace', rankings[1][0].name
    assert_score_equal 351.0, rankings[1][1]
  end

  test "list missing" do
    missing = Player.find_by(name: 'Borlin').missing_top_ns(3, nil, false)

    assert_equal @levels[3].name, missing[0]
    assert_equal 1, missing.length
  end

  test "list scores by rank" do
    scores = Player.find_by(name: 'xela').scores_by_rank

    assert_equal 0, scores[0].length
    assert_equal [@levels[1], @levels[2], @levels[3]].sort, scores[1].map { |s| s.highscoreable }.sort
    assert_equal [@levels[0]], scores[2].map { |s| s.highscoreable }
  end

  test "score counts" do
    scores = Player.find_by(name: 'xela').score_counts

    assert_equal 0, scores[:levels][0]
    assert_equal 3, scores[:levels][1]
    assert_equal 1, scores[:levels][2]
  end

  test "list improvable" do
    scores = Player.find_by(name: 'xela').improvable_scores

    assert_score_equal 2.0, scores[@levels[0].name]
    assert_score_equal 1.0, scores[@levels[1].name]
    assert_score_equal 0.0, scores[@levels[2].name]
    assert_score_equal 0.0, scores[@levels[3].name]
  end
end
