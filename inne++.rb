require 'ascii_charts'
require 'discordrb'
require 'json'
require 'net/http'
require 'thread'
require 'yaml'
require_relative 'models.rb'

require 'byebug'

TOKEN = 'Mjg5MTQxNzc2MjA2MjY2MzY5.C6IDyQ.1B1a2x_k7CF4UfaGWvhbGFVqdqM'
CLIENT_ID = 289141776206266369

HIGHSCORE_UPDATE_FREQUENCY = 30 * 60 # every 30 minutes
LEVEL_UPDATE_FREQUENCY = 24 * 60 * 60 # daily
EPISODE_UPDATE_FREQUENCY = 7 * 24 * 60 * 60 # weekly

LEVEL_PATTERN = /S[IL]?-[ABCDEX]-[0-9][0-9]-[0-9][0-9]/i
EPISODE_PATTERN = /S[IL]?-[ABCDEX]-[0-9][0-9]/i

DATABASE_ENV = ENV['DATABASE_ENV'] || 'development'

def log(msg)
  puts "[INFO] [#{Time.now}] #{msg}"
end

def err(msg)
  STDERR.puts "[ERROR] [#{Time.now}] #{msg}"
end

def parse_type(msg)
  (msg[/level/i] ? Level : (msg[/episode/i] ? Episode : nil))
end

def get_next(type)
  ret = type.where(completed: nil).sample
  ret.update(completed: true)
  ret
end

def send_top_n_count(event)
  msg = event.content
  player = Player.parse(event.content, event.user.name)

  n = ((msg[/top ([0-9][0-9]?)/i, 1]) || 1).to_i
  ties = !!(msg =~ /ties/i)
  type = parse_type(msg)

  count = player.top_n_count(n, type, ties)

  header = (n == 1 ? "0th" : "top #{n}")
  type = (type || 'overall').to_s.downcase
  event << "#{player.name} has #{count} #{type} #{header} scores#{ties ? " with ties" : ""}."
end

def send_top_n_rankings(event)
  msg = event.content

  n = ((msg[/top ([0-9][0-9]?)/i, 1]) || 1).to_i
  type = parse_type(msg)
  ties = !!(msg =~ /ties/i)

  top = Player.top_n_rankings(n, type, ties)
        .take(20)
        .each_with_index
        .map { |r, i| "#{HighScore.format_rank(i)}: #{r[0].name} (#{r[1]})" }
        .join("\n\t")

  header = (n == 1 ? "0th" : "top #{n}")
  type = (type || 'Overall').to_s
  event << "#{type} #{header} rankings #{ties ? "with ties " : ""}at #{Time.now}:\n\t#{top}"
end

# Message keyword: 'spread'
#
# Optional keywords:
#   'smallest' (assumes biggest)
#   '[rank]' (assumes 1st, options [0-9][0-9]?(st|nd|th))
#   'episode' (assumes level)
def send_spreads(event)
  msg = event.content
  n = (msg[/([0-9][0-9]?)(st|nd|th)/, 1] || 1).to_i
  episode = !!(msg =~ /episode/)
  smallest = !!(msg =~ /smallest/)

  if n == 0
    event << "I can't show you the spread between 0th and 0th..."
    return
  end

  type = episode ? Episode : Level
  spreads = HighScore.spreads(n, type)
            .sort_by { |level, spread| (smallest ? spread : -spread) }
            .take(20)
            .map { |s| "#{s[0]} (#{"%.3f" % [s[1]]})"}
            .join("\n\t")

  spread = smallest ? "smallest" : "largest"
  rank = (n == 1 ? "1st" : (n == 2 ? "2nd" : (n == 3 ? "3rd" : "#{n}th")))
  event << "#{type} with the #{spread} spread between 0th and #{rank}:\n\t#{spreads}"
end

# Format of message:
# '@inne++.*scores.*<<episode>|<level>>'
def send_scores(event)
  msg = event.content
  level = msg[LEVEL_PATTERN]
  episode = msg[EPISODE_PATTERN]
  scores = []

  if level
    scores = Level.find_by(name: level.upcase)
  elsif episode
    scores = Episode.find_by(name: episode.upcase)
  else
    event << "Sorry, I couldn't figure out what scores you wanted :("
    event << "You need to send a message with a level that looks like 'SI-A-00-00', or an episode that looks like 'SI-A-00'."
    return
  end

  scores.download_scores
  event << "Current high scores for #{level ? level : episode}:\n```#{scores.format_scores}```"
end

# Format of message:
# '@inne++.*screenshot.*<level>'
def send_screenshot(event)
  msg = event.content
  level = msg[LEVEL_PATTERN]

  if !level
    event << "Sorry, I couldn't figure out what level you were talking about :("
    event << "You need to send a message with a level that looks like 'SI-A-00-00'."
    return
  end

  level = level.upcase

  screenshot = "screenshots/#{level}.jpg"

  if File.exist? screenshot
    event.attach_file(File::open(screenshot))
  else
    event << "I don't have a screenshot for #{level}... :("
  end
end

# Format of message:
# '@inne++.*stat(s|istics).*for <username>[.?]'
def send_stats(event)
  player = Player.parse(event.content, event.user.name)
  if player.nil?
    event << "I couldn't find a player with your username!"
    return
  end

  counts = player.score_counts

  histdata = counts[:levels].zip(counts[:episodes])
             .each_with_index
             .map { |a, i| [i, a[0] + a[1]]}

  histogram = AsciiCharts::Cartesian.new(
    histdata,
    bar: true,
    hide_zero: true,
    max_y_vals: 15,
    title: 'Score histogram'
  ).draw

  totals = counts[:levels].zip(counts[:episodes])
           .each_with_index
           .map { |a, i| "#{HighScore.format_rank(i)}: #{"\t%3d   \t%3d\t\t %3d" % [a[0] + a[1], a[0], a[1]]}" }
           .join("\n\t")

  overall = "Totals: \t%3d   \t%3d\t\t %3d" % counts[:levels].zip(counts[:episodes])
            .map { |a| [a[0] + a[1], a[0], a[1]] }
            .reduce([0, 0, 0]) { |sums, curr| sums.zip(curr).map { |a| a[0] + a[1] } }

  event << "Player high score counts for #{player.name}:\n```\t    Overall:\tLevel:\tEpisode:\n\t#{totals}\n#{overall}"
  event << "#{histogram}```"
end

def send_list(event)
  player = Player.parse(event.content, event.user.name)

  all = player.scores_by_rank
  tmpfile = "scores-#{player.name}.txt"

  File::open(tmpfile, "w") do |f|
    all.each_with_index do |scores, i|
      list = scores.map { |s| "#{HighScore.format_rank(s.rank)}: #{s.highscoreable.name} (#{"%.3f" % [s.score]})" }
             .join("\n  ")
      f.write("#{i}:\n  ")
      f.write(list)
      f.write("\n")
    end
  end

  event.attach_file(File::open(tmpfile))
  # TODO we can't delete this right here...
  # File::delete(tmpfile)
end

def send_suggestions(event)
  msg = event.content
  player = Player.parse(msg, event.user.name)

  type = ((msg[/level/] || !msg[/episode/]) ? Level : Episode)
  n = (msg[/\b[0-9][0-9]?\b/] || 10).to_i

  if player.nil?
    event << "I couldn't figure out who you were asking about :("
    return
  end

  improvable = player.improvable_scores(type)
               .sort_by { |level, gap| -gap }
               .take(n)
               .map { |level, gap| "#{level} (-#{"%.3f" % [gap]})" }
               .join("\n")

  missing = player.missing_scores(type).sample(n).join("\n")
  type = type.to_s.downcase

  event << "Your #{n} most improvable #{type}s are:\n```#{improvable}```"
  event << "You're not on the board for:\n```#{missing}```"
end

def identify(event)
  msg = event.content
  user = event.user.name
  nick = msg[/my name is (.*)[\.]?$/i, 1]

  if nick.nil?
    event << "I couldn't figure out who you were! You have to send a message in the form 'my name is <username>.'"
    return
  end

  player = Player.find_or_create_by(name: nick)
  user = User.create(username: user)
  user.player = player
  user.save

  event << "Awesome! From now on you can omit your username and I'll look up scores for #{nick}."
end

def hello(event)
  event << "Hi!"

  if $channel.nil?
    $channel = event.channel
    send_times(event)
  end
end

def send_level_time(event)
  next_level = $next_level_update - Time.now
  next_level_hours = (next_level / (60 * 60)).to_i
  next_level_minutes = (next_level / 60).to_i - (next_level / (60 * 60)).to_i * 60

  event << "I'll post a new level of the day in #{next_level_hours} hours and #{next_level_minutes} minutes."
end

def send_episode_time(event)
  next_episode = $next_episode_update - Time.now
  next_episode_days = (next_episode / (24 * 60 * 60)).to_i
  next_episode_hours = (next_episode / (60 * 60)).to_i - (next_episode / (24 * 60 * 60)).to_i * 24

  event << "I'll post a new episode of the week in #{next_episode_days} days and #{next_episode_hours} hours."
end

def send_times(event)
  send_level_time(event)
  send_episode_time(event)
end

def send_level(event)
  event << "The current level of the day is #{$current[:level]}."
end

def send_episode(event)
  event << "The current episode of the day is #{$current[:episode]}."
end

def dump(event)
  log("current level/episode: #{$current}")
  log("next updates: scores #{$next_score_update}, level #{$next_level_update}, episode #{$next_episode_update}")

  event << "I dumped some things to the log for you to look at."
end

def download_high_scores
  ActiveRecord::Base.establish_connection(YAML.load_file('db/config.yml')[DATABASE_ENV])

  while true
    log("updating high scores...")

    Level.all.each(&:download_scores)
    Episode.all.each(&:download_scores)

    $next_score_update += HIGHSCORE_UPDATE_FREQUENCY
    delay = $next_score_update - Time.now

    log("updated scores, next score update in #{delay} seconds")
    sleep(delay) unless delay < 0
  end
end

def send_channel_screenshot(name, caption)
    screenshot = "screenshots/#{name}.jpg"
    if File.exist? screenshot
      $channel.send_file(File::open(screenshot), caption: caption)
    else
      $channel.send_message(caption + "\nI don't have a screenshot for this one... :(")
    end
end

def send_channel_diff(level, old_scores, since)
  return if level.nil? || old_scores.nil?

  diff = level.format_difference(old_scores)
  $channel.send_message("Score changes on #{level.name} since #{since}:\n```#{diff}```")
end

def start_level_of_the_day
  saved_scores = {}

  while true
    sleep($next_level_update - Time.now)
    $next_level_update += LEVEL_UPDATE_FREQUENCY

    if $channel.nil?
      err("not connected to a channel, not sending level of the day")
      next
    end

    last_level = $current[:level]
    $current[:level] = get_next(Level)

    if !$current[:level]
      err("no more levels")
      break
    end

    caption = "Time for a new level of the day! The level for today is #{$current[:level].name}."
    send_channel_screenshot($current[:level].name, caption)
    $channel.send_message("Current high scores:\n```#{$current[:level].format_scores}```")

    send_channel_diff(last_level, saved_scores[:level], "yesterday")
    saved_scores[:level] = $current[:level].scores.to_json(include: {player: {only: :name}})

    if Time.now > $next_episode_update
      $next_episode_update += EPISODE_UPDATE_FREQUENCY
      sleep(30) # let discord catch up

      last_episode = $current[:episode]
      $current[:episode] = get_next(Episode)
      if !$current[:episode]
        err("no more episodes")
        break
      end

      $original_scores[:episode] = $current[:episode].scores.to_json(include: {player: {only: :name}})

      caption = "It's also time for a new episode of the week! The episode for this week is #{$current[:episode].name}."
      send_channel_screenshot($current[:episode].name, caption)
      $channel.send_message("Current high scores:\n```#{$current[:episode].format_scores}```")

      send_channel_diff(last_episode, saved_scores[:episode], "last week")
      saved_scores[:episode] = $current[:episode].scores.to_json(include: {player: {only: :name}})
    end
  end
end

def startup
  now = Time.now
  $next_score_update = now

  $next_level_update = DateTime.new(now.year, now.month, now.day + 1, 0, 0, 0, now.zone)
  $next_episode_update = $next_level_update

  while !$next_episode_update.saturday?
    $next_episode_update = $next_episode_update + 1
  end

  $next_level_update = $next_level_update.to_time
  $next_episode_update = $next_episode_update.to_time

  # $next_level_update = $next_score_update + LEVEL_UPDATE_FREQUENCY
  # $next_episode_update = $next_score_update + EPISODE_UPDATE_FREQUENCY

  log("initialized")
  log("next level update at #{$next_level_update.to_s}")
  log("next episode update at #{$next_episode_update.to_s}")
  log("next score update at #{$next_score_update}")

  ActiveRecord::Base.establish_connection(YAML.load_file('db/config.yml')[DATABASE_ENV])
end

def shutdown
  log("shutting down")

  $bot.stop

  log("wrote data files")
end

def watchdog
  sleep(3) while !$kill_threads
  shutdown
end

def respond(event)
  hello(event) if event.content =~ /\bhello\b/i || event.content =~ /\bhi\b/i
  dump(event) if event.content =~ /dump/i
  send_episode_time(event) if event.content =~ /when.*next.*(episode|eotw)/i
  send_level_time(event) if  event.content =~ /when.*next.*(level|lotd)/i
  send_level(event) if event.content =~ /what.*(level|lotd)/i
  send_episode(event) if event.content =~ /what.*(episode|eotw)/i
  send_top_n_rankings(event) if event.content =~ /rankings/i
  send_top_n_count(event) if event.content =~ /how many/i
  send_stats(event) if event.content =~ /stat/i
  send_spreads(event) if event.content =~ /spread/i
  send_screenshot(event) if event.content =~ /screenshot/i
  send_scores(event) if event.content =~ /scores/i
  send_suggestions(event) if event.content =~ /worst/i
  send_list(event) if event.content =~ /list/i
  identify(event) if event.content =~ /my name is/i
rescue RuntimeError => e
  event << e
end

$bot = Discordrb::Bot.new token: TOKEN, client_id: CLIENT_ID
$channel = nil
$current = {level: nil, episode: nil}
$original_scores = {level: nil, episode: nil}

$next_score_update = nil
$next_level_update = nil
$next_episode_update = nil

$old = nil
$old_level = nil

$bot.mention do |event|
  respond(event)
  log("mentioned by #{event.user.name}: #{event.content}")
end

$bot.private_message do |event|
  respond(event)
  log("private message from #{event.user.name}: #{event.content}")
end

puts "the bot's URL is #{$bot.invite_url}"

startup
trap("INT") { $kill_threads = true }

$threads = [
  Thread.new { start_level_of_the_day },
  Thread.new { download_high_scores },
]

$bot.run(true)

wd = Thread.new { watchdog }
wd.join
