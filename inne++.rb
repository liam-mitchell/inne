require 'ascii_charts'
require 'discordrb'
require 'json'
require 'net/http'
require 'thread'

TOKEN = 'Mjg5MTQxNzc2MjA2MjY2MzY5.C6IDyQ.1B1a2x_k7CF4UfaGWvhbGFVqdqM'
CLIENT_ID = 289141776206266369

HIGHSCORES_FILE = 'highscores.json'
COMPLETED_FILE = 'completed.json'
USERS_FILE = 'users.json'

HIGHSCORE_UPDATE_FREQUENCY = 30 * 60 # every 30 minutes
LEVEL_UPDATE_FREQUENCY = 24 * 60 * 60 # daily
EPISODE_UPDATE_FREQUENCY = 7 * 24 * 60 * 60 # weekly

LEVEL_PATTERN = /S[IL]?-[ABCDEX]-[0-9][0-9]-[0-9][0-9]/i
EPISODE_PATTERN = /S[IL]?-[ABCDEX]-[0-9][0-9]/i

IGNORED_PLAYERS = [
  "Kronogenics",
  "BlueIsTrue",
  "fiordhraoi",
]

def log(msg)
  puts "[LOG] [#{Time.now}] #{msg}"
end

def err(msg)
  STDERR.puts "[ERR] [#{Time.now}] #{msg}"
end

def scores_uri(id, episode = false)
  URI("https://dojo.nplusplus.ninja/prod/steam/get_scores?steam_id=76561197992013087&steam_auth=&#{episode ? "episode" : "level"}_id=#{id}")
end

def download_scores(id, type)
  if type != "levels" && type != "episodes"
    err("incorrect type in get_scores: #{type}")
    return nil
  end

  uri = scores_uri(type == "levels" ? level_id(id) : episode_id(id))
  response = Net::HTTP.get(uri)

  if response == "-1337"
    err("failed to retrieve scores from #{uri}")
    return nil
  end

  # Sort by rank, except in the case where the scores are tied. For ties, the API returns scores sorted
  # in reverse (compared to the N++ ingame UI). So, flip those ones.
  # Then, use their index in this list instead of the rank, because the rank is wrong.
  JSON.parse(response)["scores"].sort { |a, b| a["score"] == b["score"] ? b["rank"] <=> a["rank"] : a["rank"] <=> b["rank"] }
    .select { |score| !IGNORED_PLAYERS.include?(score["user_name"]) }
    .each_with_index
    .map { |score, i| {"rank" => i, "user" => score["user_name"], "score" => score["score"] / 1000.0} }
end

def format_rank(rank)
  "#{rank < 10 ? "0" : ""}#{rank}"
end

def format_score(score)
  "#{format_rank(score["rank"])}: #{score["user"]} (#{"%.3f" % [score["score"].round(3)]})"
end

def format_scores(scores)
  scores.map { |score| format_score(score) }.join("\n\t")
end

def get_scores(id, type)
  $score_lock.synchronize do
    $highscores[type][id] = download_scores(id, type)
    $highscores[type][id]
  end
end

def levels(episodes)
  episodes.product((0..4).to_a).map { |a| a.join("-0") }
end

def episodes
  intro = ["SI"].product(["A", "B", "C", "D", "E"])
          .product((0..4).to_a)

  main = ["S", "SL"].product(["A", "B", "C", "D", "E", "X"])
         .product((0..19).to_a)

  (intro + main).map(&:flatten).map do |prefix, row, column|
    column = "0" + column.to_s if column < 10
    [prefix, row, column.to_s].join("-")
  end
end

def level_id(level)
  episode_id(level) * 5 + level[/[0-9][0-9]$/].to_i
end

def episode_id(episode)
  first_episodes = {"SI" => 0, "S" => 120, "SL" => 240}

  prefix, row, column = episode.split("-")
  column = column.to_i

  id = first_episodes[prefix.upcase]

  if row !~ /X/i
    id += column * 5
    id += row.upcase.ord - "A".ord
  else
    id += column + 100
  end

  id
end

def score_spreads(n, type)
  spreads = {}

  $score_lock.synchronize do
    $highscores[type].each do |id, scores|
      i = (n < scores.length ? n : scores.length - 1)
      spreads[id] = scores[0]["score"] - scores[i]["score"]
    end
  end

  spreads
end

def score_top_n_rankings(n, type, ties)
  rankings = Hash.new { |h, k| h[k] = 0 }

  $score_lock.synchronize do
    $highscores[type].each do |id, scores|
      scores.take_while { |score| score["rank"] < n || (ties && (score["score"] == scores[n]["score"])) }
        .each { |score| rankings[score["user"]] += 1 }
    end
  end

  rankings
end

def improvable_scores(player, type)
  improvable = {}

  $score_lock.synchronize do
    $highscores[type].each do |id, scores|
      i = scores.find_index { |score| score["user"] == player }
      improvable[id] = scores[0]["score"] - scores[i]["score"] unless i.nil?
    end
  end

  improvable
end

def missing_scores(player, type)
  $score_lock.synchronize do
    $highscores[type].map do |id, scores|
      if scores.find_index { |score| score["user"] == player }.nil?
        id
      else
        nil
      end
    end
  end.compact.flatten
end

def parse_username(event)
  user = event.content[/for (.*)[\.\?]?/i, 1]
  user = $users[event.user.name] if user == "me" || user.nil?
  user
end

# Format of message:
# '@inne++.*top 10.*[level|episode].*rank.*'
# '@inne++.*0th.*[level|episode].*rank.*'
def send_top_n_rankings(event)
  msg = event.content

  n = (msg =~ /0th/i ? 1 : msg[/top ([0-9][0-9]?)/i, 1].to_i)
  level = !!(msg =~ /level/i || msg !~ /episode/i)
  episode = !!(msg =~ /episode/i || msg !~ /level/i)
  ties = !!(msg =~ /ties/i)

  rankings = {}

  if level
    rankings = score_top_n_rankings(n, "levels", ties)
  end

  if episode
    rankings.merge!(score_top_n_rankings(n, "episodes", ties)) { |key, old, new| old + new }
  end

  top = rankings.sort_by { |player, count| -count }
        .take(20)
        .each_with_index
        .map { |r, i| "#{format_rank(i)}: #{r[0]} (#{r[1]})" }
        .join("\n\t")

  header = (n == 1 ? "0th" : "Top #{n}")
  type = (level ^ episode) ? (level ? "Level" : "Episode") : "Overall"
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

  type = episode ? "Episodes" : "Levels"
  spreads = score_spreads(n, type.downcase)
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
    scores = get_scores(level, "levels")
  elsif episode
    scores = get_scores(episode, "episodes")
  else
    event << "Sorry, I couldn't figure out what scores you wanted :("
    event << "You need to send a message with a level that looks like 'SI-A-00-00', or an episode that looks like 'SI-A-00'."
    return
  end

  event << "Current high scores for #{level ? level : episode}:\n\t#{format_scores(scores)}"
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
  # username = event.content[/for (.*)[\.\?]?/i, 1]
  username = parse_username(event)
  if username.empty?
    event << "Sorry, I couldn't figure out a username :( You need to send a message that ends with 'for <username>'."
    return
  end

  counts = {"levels" => Array.new(20, 0), "episodes" => Array.new(20, 0)}

  $score_lock.synchronize do
    $highscores.each do |type, values|
      values.each do |id, scores|
        scores.each do |score|
          if score["user"] == username
            counts[type][score["rank"]] += 1
          end
        end
      end
    end
  end

  histdata = counts["levels"].zip(counts["episodes"])
             .each_with_index
             .map { |a, i| [i, a[0] + a[1]]}

  histogram = AsciiCharts::Cartesian.new(histdata, bar: true, hide_zero: true).draw

  totals = counts["levels"].zip(counts["episodes"])
           .each_with_index
           .map { |a, i| "#{format_rank(i)}: #{"%3d         %3d       %3d" % [a[0] + a[1], a[0], a[1]]}" }
           .join("\n\t")

  overall = "Totals: %3d         %3d       %3d" % counts["levels"].zip(counts["episodes"])
            .map { |a| [a[0] + a[1], a[0], a[1]] }
            .reduce([0, 0, 0]) { |sums, curr| sums.zip(curr).map { |a| a[0] + a[1] } }

  event << "Player high score counts for #{username}:\n```\t    Overall:\tLevel:\tEpisode:\n\t#{totals}\n#{overall}```"
  event << "Player score histogram: \n```#{histogram}```"
end

def send_suggestions(event)
  msg = event.content
  player = parse_username(event)

  type = ((msg[/level/] || !msg[/episode/]) ? "levels" : "episodes")
  n = (msg[/\b[0-9][0-9]?\b/] || 10).to_i
  log("getting #{player} worst scores for #{type}")

  if player.nil?
    event << "I couldn't figure out who you were asking about :("
    return
  end

  improvable = improvable_scores(player, type)
               .sort_by { |level, gap| -gap }
               .take(n)
               .map { |level, gap| "#{level} (-#{"%.3f" % [gap]})" }
               .join("\n\t")

  missing = missing_scores(player, type).sample(n).join("\n\t")

  event << "Your #{n} most improvable #{type} are:\n\t#{improvable}.\nYou're not on the board for:\n\t#{missing}."
end

def identify(event)
  msg = event.content
  user = event.user.name
  nick = msg[/my name is (.*)[\.]?$/i, 1]

  if nick.nil?
    event << "I couldn't figure out who you were! You have to send a message in the form 'my name is <username>.'"
    return
  end

  $users[user] = nick
  event << "Awesome! From now on you can just say 'me' and I'll look up scores for #{nick}."
end

def random_element(array)
  return nil if array.length == 0
  array.delete_at(rand(array.length))
end

def hello(event)
  event << "Hi!"

  if $channel.nil?
    $channel = event.channel
    send_times(event)
  end
end

def send_times(event)
  next_level = $next_level_update - Time.now
  next_episode = $next_episode_update - Time.now

  next_level_hours = (next_level / (60 * 60)).to_i
  next_level_minutes = (next_level / 60).to_i - (next_level / (60 * 60)).to_i * 60
  next_episode_days = (next_episode / (24 * 60 * 60)).to_i

  event << "I'll post a new level of the day in #{next_level_hours} hours and #{next_level_minutes} minutes, and a new episode of the week in #{next_episode_days} days."
end

def send_level(event)
  event << "The current level of the day is #{$current[:level]}."
end

def dump(event)
  log("high scores: #{$highscores}")
  log("completed levels/episodes: #{$completed}")
  log("current level/episode: #{$current}")
  log("next updates: scores #{$next_score_update}, level #{$next_level_update}, episode #{$next_episode_update}")

  event << "I dumped some things to the log for you to look at."
end

def download_high_scores
  while true
    log("updating high scores...")

    # Sleep here to give other threads a chance to lock $score_lock and read high scores
    # If we don't sleep this thread basically always has the lock and querying stats takes
    # a very long time
    $levels.each do |level|
      get_scores(level, "levels");
      sleep(0.01)
    end

    $episodes.each do |episode|
      get_scores(episode, "episodes");
      sleep(0.01)
    end

    $next_score_update += HIGHSCORE_UPDATE_FREQUENCY
    delay = $next_score_update - Time.now

    log("updated scores, next score update in #{delay} seconds")
    sleep(delay) unless delay < 0
  end
end

def start_level_of_the_day
  while true
    sleep($next_level_update - Time.now)
    $next_level_update += LEVEL_UPDATE_FREQUENCY

    if $channel.nil?
      err("not connected to a channel, not sending level of the day")
      next
    end

    $current[:level] = random_element($levels)
    $completed["levels"] |= [$current[:level]]

    err("no more levels") if $current[:level].nil?

    $channel.send_message("Time for a new level of the day! The level for today is #{$current[:level]}.")

    screenshot = "screenshots/#{$current[:level]}.jpg"
    if File.exist? screenshot
      $channel.send_file(File::open(screenshot))
    else
      $channel.send_message("I don't have a screenshot for this one... :(")
    end

    $channel.send_message("Current high scores: \n\t#{format_scores(level_scores($current[:level]))}")

    if Time.now > $next_episode_update
      $next_episode_update += EPISODE_UPDATE_FREQUENCY

      $current[:episode] = random_element($episodes)
      $completed["episodes"] |= [$current[:episode]]

      err("no more episodes") if $current[:episode].nil?

      $channel.send_message("It's also time for a new episode of the week! The episode for this week is #{$current[:episode]}.")
      $channel.send_message("Current high scores: \n\t#{format_scores(episode_scores($current[:episode]))}")
    end
  end
end

def startup
  $highscores = JSON.parse(File.read(HIGHSCORES_FILE)) if File.exist?(HIGHSCORES_FILE)
  $completed = JSON.parse(File.read(COMPLETED_FILE)) if File.exist?(COMPLETED_FILE)
  $users = JSON.parse(File.read(USERS_FILE)) if File.exist?(USERS_FILE)

  $highscores ||= {"levels" => {}, "episodes" => {}}
  $completed ||= {"levels" => [], "episodes" => []}
  $users ||= {}

  $completed["levels"].each { |level| $levels.delete(level) }
  $completed["episodes"].each { |episode| $episodes.delete(episode) }

  now = Time.now
  $next_score_update = now

  $next_level_update = DateTime.new(now.year, now.month, now.day + 1, 0, 0, 0, now.zone)
  $next_episode_update = $next_level_update

  while !$next_episode_update.saturday?
    $next_episode_update = $next_episode_update + 1
  end

  $next_level_update = $next_level_update.to_time
  $next_episode_update = $next_episode_update.to_time

  log("initialized")
  log("next level update at #{$next_level_update.to_s}")
  log("next episode update at #{$next_episode_update.to_s}")
  log("next score update at #{$next_score_update}")
end

def shutdown
  log("shutting down")

  $bot.stop

  # Make sure the high scores thread is done writing to $highscores before we
  # kill it.
  $score_lock.synchronize do
    $threads.each { |t| t.kill }
  end

  # Now we can safely write $highscores to file without reading bad data.
  File.open(HIGHSCORES_FILE, "w") { |f| f.write($highscores.to_json) }
  File.open(COMPLETED_FILE, "w") { |f| f.write($completed.to_json) }
  File.open(USERS_FILE, "w") { |f| f.write($users.to_json) }

  log("wrote data files")
end

def watchdog
  sleep(3) while !$kill_threads
  shutdown
end

$bot = Discordrb::Bot.new token: TOKEN, client_id: CLIENT_ID
$channel = nil
$current = {level: nil, episode: nil}
$completed = nil

$score_lock = Mutex.new
$threads = []
$kill_threads = false

$episodes = episodes
$levels = levels($episodes)

$highscores = {"levels" => {}, "episodes" => {}}
$users = {}

$next_score_update = nil
$next_level_update = nil
$next_episode_update = nil

puts "the bot's URL is #{$bot.invite_url}"

def respond(event)
  hello(event) if event.content =~ /hello/i || event.content =~ /hi/i
  dump(event) if event.content =~ /dump/i
  send_times(event) if event.content =~ /when.*next/i
  send_level(event) if event.content =~ /what( is|'s).*(level|lotd)/i
  send_top_n_rankings(event) if event.content =~ /(0th|top [0-9][0-9]?).*rank/i
  send_stats(event) if event.content =~ /stat/i
  send_spreads(event) if event.content =~ /spread/i
  send_screenshot(event) if event.content =~ /screenshot/i
  send_scores(event) if event.content =~ /scores/i
  send_suggestions(event) if event.content =~ /worst/i
  identify(event) if event.content =~ /my name is/i
end

$bot.mention do |event|
  respond(event)
  log("mentioned by #{event.user.name}: #{event.content}")
end

$bot.private_message do |event|
  respond(event)
  log("private message from #{event.user.name}: #{event.content}")
end

startup
trap("INT") { $kill_threads = true }

$threads = [
  Thread.new { start_level_of_the_day },
  Thread.new { download_high_scores },
]

$bot.run(true)

wd = Thread.new { watchdog }
wd.join
