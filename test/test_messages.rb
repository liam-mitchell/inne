class TestMessages < Test::Unit::TestCase
  def setup
    DatabaseCleaner.start

    @players = [
      create(:player, name: 'xela'),
      create(:player, name: 'Borlin'),
      create(:player, name: 'jp27ace'),
      create(:player, name: 'EddyMataGallos'),
      create(:player, name: 'TOAST BUSTERS'),
      create(:player, name: 'golfkid'),
      create(:player, name: 'Maaz :D'),
      create(:player, name: 'High Priest o the Righteous Feed'),
      create(:player, name: 'Jirka'),
      create(:player, name: 'overlordlork'),
      create(:player, name: 'Muzgrob'),
      create(:player, name: 'Squadxzo'),
      create(:player, name: 'muratcantonta'),
      create(:player, name: 'Untamed Nim'),
      create(:player, name: 'Personman'),
      create(:player, name: 'Chewyy'),
      create(:player, name: 'oxygen_'),
      create(:player, name: 'ibcamwhobu'),
      create(:player, name: 'Msyjsm'),
      create(:player, name: 'Line Rider 0')
    ]

    @levels = 4.times.map { |i| create(:level) }
    @episode = create(:episode)
    @levels << @episode

    @scores = @levels.map { |l| 20.times.map { |i| create(:score, highscoreable: l, player: @players[i], rank: i, score: 90.000 - i) } }
  end

  def teardown; DatabaseCleaner.clean; end
  def get_next_update(type); Time.now; end
  def get_current(type)
    type == Episode ? @episode : @levels[0]
  end

  test "says hello" do
    event = mock('object')
    event.expects(:content).returns('hello').at_least(1)
    event.expects(:<<).with('Hi!')
    event.expects(:<<).with(regexp_matches(/I'll post a new level of the day in.*/))
    event.expects(:<<).with(regexp_matches(/I'll post a new episode of the week in.*/))
    event.expects(:channel).returns(nil)

    respond(event)
  end

  test "sends next level update" do
    event = mock('object')
    event.expects(:content).returns('when\'s the next lotd').at_least(1)
    event.expects(:<<).with(regexp_matches(/I'll post a new level of the day in.*/))

    respond(event)
  end

  test "sends next episode update" do
    event = mock('object')
    event.expects(:content).returns('when\'s the next eotw').at_least(1)
    event.expects(:<<).with(regexp_matches(/I'll post a new episode of the week in.*/))

    respond(event)
  end

  test "sends current level" do
    event = mock('object')
    event.expects(:content).returns('what\'s the lotd').at_least(1)
    event.expects(:<<).with(regexp_matches(/The current level of the day is.*/))

    respond(event)
  end

  test "sends current episode" do
    event = mock('object')
    event.expects(:content).returns('what\'s the eotw').at_least(1)
    event.expects(:<<).with(regexp_matches(/The current episode of the week is.*/))

    respond(event)
  end

  test "sends rankings" do
    event = mock('object')
    event.expects(:content).returns('top 20 rank').at_least(1)
    event.expects(:<<).with(regexp_matches(/Overall top 20 rankings.*:.```([0-9][0-9]: .* \([0-9]+\).?){20}```/m))

    respond(event)
  end

  test "sends 0th rankings" do
    event = mock('object')
    event.expects(:content).returns('rank').at_least(1)
    event.expects(:<<).with(regexp_matches(/Overall 0th rankings.*:.```([0-9][0-9]: .* \([0-9]+\).?){1,20}```/m))

    respond(event)
  end

  test "sends 0th rankings with ties" do
    event = mock('object')
    event.expects(:content).returns('rank with ties').at_least(1)
    event.expects(:<<).with(regexp_matches(/Overall 0th rankings with ties.*:.```([0-9][0-9]: .* \([0-9]+\).?){1,20}```/m))

    respond(event)
  end

  test "sends score rankings" do
    event = mock('object')
    event.expects(:content).returns('score rank').at_least(1)
    event.expects(:<<).with(regexp_matches(/Overall score rankings.*:.```([0-9][0-9]: .* \([0-9]+\.[0-9]{3}\).?){1,20}```/m))

    respond(event)
  end

  test "sends point rankings" do
    event = mock('object')
    event.expects(:content).returns('point rank').at_least(1)
    event.expects(:<<).with(regexp_matches(/Overall point rankings.*:.```([0-9][0-9]: .* \([0-9]+\).?){1,20}```/m))

    respond(event)
  end

  test "sends points" do
    event = mock('object')

    user = mock('object')
    user.expects('name').returns('')
    event.expects(:user).returns(user)

    event.expects(:content).returns('points for xela').at_least(1)
    event.expects(:<<).with(regexp_matches(/xela has [0-9]+ overall points./))

    respond(event)
  end

  test "sends count" do
    event = mock('object')

    user = mock('object')
    user.expects('name').returns('')
    event.expects(:user).returns(user)

    event.expects(:content).returns('how many 0ths for xela').at_least(1)
    event.expects(:<<).with(regexp_matches(/xela has [0-9]+ overall 0th scores./))

    respond(event)
  end

  test "sends stats" do
    event = mock('object')

    user = mock('object')
    user.expects('name').returns('')
    event.expects(:user).returns(user)

    event.expects(:content).returns('stats for xela').at_least(1)
    event.expects(:<<).with(regexp_matches(/Player high score counts for xela:.```.*Overall:.Level:.Episode:.*Totals:.*/m))
    event.expects(:<<).with(regexp_matches(/.*Score histogram.*```/m))

    respond(event)
  end

  test "sends spreads" do
    event = mock('object')

    event.expects(:content).returns('spread').at_least(1)
    event.expects(:<<).with(regexp_matches(/All levels with the largest spread between 0th and 1st:.*/))

    respond(event)
  end
end
