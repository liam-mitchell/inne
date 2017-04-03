require 'ascii_charts'
require 'discordrb'
require 'json'
require 'net/http'
require 'thread'
require 'yaml'
require_relative 'models.rb'

require 'byebug'

LEVEL_PATTERN = /S[IL]?-[ABCDEX]-[0-9][0-9]?-[0-9][0-9]?/i
EPISODE_PATTERN = /S[IL]?-[ABCDEX]-[0-9][0-9]?/i
NAME_PATTERN = /(for|of) (.*)[\.\?]?/i

DATABASE_ENV = ENV['DATABASE_ENV'] || 'development'
CONFIG = YAML.load_file('db/config.yml')[DATABASE_ENV]

HIGHSCORE_UPDATE_FREQUENCY = 24 * 60 * 60 # daily
LEVEL_UPDATE_FREQUENCY = CONFIG['level_update_frequency'] || 24 * 60 * 60 # daily
EPISODE_UPDATE_FREQUENCY = CONFIG['episode_update_frequency'] || 7 * 24 * 60 * 60 # weekly

def log(msg)
  puts "[INFO] [#{Time.now}] #{msg}"
end

def err(msg)
  STDERR.puts "[ERROR] [#{Time.now}] #{msg}"
end

def get_current(type)
  type.find_by(name: GlobalProperty.find_by(key: "current_#{type.to_s.downcase}").value)
end

def set_current(type, curr)
  GlobalProperty.find_or_create_by(key: "current_#{type.to_s.downcase}").update(value: curr.name)
end

def get_next_update(type)
  $lock.synchronize do
    Time.parse(GlobalProperty.find_by(key: "next_#{type.to_s.downcase}_update").value)
  end
end

def set_next_update(type, time)
  $lock.synchronize do
    GlobalProperty.find_or_create_by(key: "next_#{type.to_s.downcase}_update").update(value: time.to_s)
  end
end

def get_saved_scores(type)
  JSON.parse(GlobalProperty.find_by(key: "saved_#{type.to_s.downcase}_scores").value)
end

def set_saved_scores(type, curr)
  GlobalProperty.find_or_create_by(key: "saved_#{type.to_s.downcase}_scores")
    .update(value: curr.scores.to_json(include: {player: {only: :name}}))
end

# TODO do all this parsing here
# it doesn't make sense to do it in models
# and throw exceptions in all of them consistently
def parse_type(msg)
  (msg[/level/i] ? Level : (msg[/episode/i] ? Episode : nil))
end

def normalize_name(name)
  name.split('-').map { |s| s[/\A[0-9]\Z/].nil? ? s : "0#{s}" }.join('-')
end

def parse_player(msg, username)
  p = msg[/for (.*)[\.\?]?/i, 1]

  if p.nil?
    raise "I couldn't find a player with your username! Have you identified yourself (with '@inne++ my name is <N++ display name>')?" unless User.exists?(username: username)
    User.find_by(username: username).player
  else
    raise "#{p} doesn't have any high scores! Either you misspelled the name, or they're exceptionally bad..." unless Player.exists?(name: p)
    Player.find_by(name: p)
  end
end

def parse_level_or_episode(msg)
  level = msg[LEVEL_PATTERN]
  episode = msg[EPISODE_PATTERN]
  name = msg[NAME_PATTERN, 2]
  ret = nil

  if level
    ret = Level.find_by(name: normalize_name(level).upcase)
  elsif episode
    ret = Episode.find_by(name: normalize_name(episode).upcase)
  elsif !msg[/(level|lotd)/].nil?
    ret = get_current(Level)
  elsif !msg[/(episode|eotw)/].nil?
    ret = get_current(Episode)
  elsif name
    ret = Level.find_by("UPPER(longname) LIKE '#{name.upcase}'")
  else
    msg = "I couldn't figure out which level or episode you wanted scores for! You need to send either a level " +
          "or episode ID that looks like SI-A-00-00 or SI-A-00, or a level name, using 'for <name>.'"
    raise msg
  end

  raise "I couldn't find anything by that name :(" if ret.nil?
  ret
end

def parse_rank(msg, dflt)
  ((msg[/top\s*([0-9][0-9]?)/i, 1]) || dflt).to_i
end

def get_next(type)
  ret = type.where(completed: nil).sample
  ret.update(completed: true)
  ret
end

def send_top_n_count(event)
  msg = event.content
  player = parse_player(msg, event.user.name)
  n = parse_rank(msg, 1)
  type = parse_type(msg)
  ties = !!(msg =~ /ties/i)

  count = player.top_n_count(n, type, ties)

  header = (n == 1 ? "0th" : "top #{n}")
  type = (type || 'overall').to_s.downcase
  event << "#{player.name} has #{count} #{type} #{header} scores#{ties ? " with ties" : ""}."
end

def send_rankings(event)
  msg = event.content
  type = parse_type(msg)
  n = parse_rank(msg, 1)
  ties = !!(msg =~ /ties/i)

  if event.content =~ /point/
    rankings = Player.rankings { |p| p.points(type) }
    header = "point rankings"
    format = "%d"
  elsif event.content =~ /score/
    rankings = Player.rankings { |p| p.total_score(type) }
    header = "score rankings"
    format = "%.3f"
  else
    rankings = Player.rankings { |p| p.top_n_count(n, type, ties) }

    rank = (n == 1 ? "0th" : "top #{n}")
    ties = (ties ? "with ties " : "")

    header = "#{rank} rankings #{ties}"
    format = "%d"
  end

  type = (type || "Overall").to_s

  top = rankings.take(20).each_with_index.map { |r, i| "#{HighScore.format_rank(i)}: #{r[0].name} (#{format % r[1]})" }
        .join("\n")

  event << "#{type} #{header} #{Time.now.strftime("on %A %B %-d at %H:%M:%S (%z)")}:\n```#{top}```"
end

def send_total_score(event)
  player = parse_player(event.content, event.user.name)
  type = parse_type(event.content)

  event << "#{player.name}'s total #{type.to_s.downcase} score is #{player.total_score(type)}."
end

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

def send_scores(event)
  msg = event.content
  scores = parse_level_or_episode(msg)
  scores.download_scores

  # Send immediately here - using << delays sending until after the event has been processed,
  # and we want to download the scores for the episode in the background after sending since it
  # takes a few seconds
  event.send_message("Current high scores for #{scores.format_name}:\n```#{scores.format_scores}```")

  if scores.is_a?(Episode)
    Level.where("UPPER(name) LIKE '#{scores.name.upcase}%'").each(&:download_scores)
  end
end

def send_screenshot(event)
  msg = event.content
  scores = parse_level_or_episode(msg)
  name = scores.name.upcase

  screenshot = "screenshots/#{name}.jpg"

  if File.exist? screenshot
    event.attach_file(File::open(screenshot))
  else
    event << "I don't have a screenshot for #{scores.format_name}... :("
  end
end

def send_stats(event)
  player = parse_player(event.content, event.user.name)
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
  player = parse_player(event.content, event.user.name)
  all = player.scores_by_rank

  tmpfile = "scores-#{player.name.delete(":")}.txt"
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

def send_missing(event)
  msg = event.content
  player = parse_player(msg, event.user.name)
  type = parse_type(msg)
  rank = parse_rank(msg, 20)
  ties = !!(msg =~ /ties/i)

  missing = player.missing_top_ns(rank, type, ties).join("\n")

  tmpfile = "missing-#{player.name.delete(":")}.txt"
  File::open(tmpfile, "w") do |f|
    f.write(missing)
  end

  event.attach_file(File::open(tmpfile))
  # TODO deleting again lol
end

def send_suggestions(event)
  msg = event.content
  player = parse_player(msg, event.user.name)

  type = ((msg[/level/] || !msg[/episode/]) ? Level : Episode)
  n = (msg[/\b[0-9][0-9]?\b/] || 10).to_i

  improvable = player.improvable_scores(type)
               .sort_by { |level, gap| -gap }
               .take(n)
               .map { |level, gap| "#{level} (-#{"%.3f" % [gap]})" }
               .join("\n")

  missing = player.missing_top_ns(20, type, false).sample(n).join("\n")
  type = type.to_s.downcase

  event << "Your #{n} most improvable #{type}s are:\n```#{improvable}```"
  event << "You're not on the board for:\n```#{missing}```"
end

def send_level_id(event)
  level = parse_level_or_episode(event.content.gsub(/level/, ""))
  event << "#{level.longname} is level #{level.name}."
end

def send_level_name(event)
  level = parse_level_or_episode(event.content.gsub(/level/, ""))
  raise "Episodes don't have a name!" if level.is_a?(Episode)
  event << "#{level.name} is called #{level.longname}."
end

def send_points(event)
  msg = event.content
  player = parse_player(msg, event.user.name)
  type = parse_type(msg)
  points = player.points(type)

  type = (type || 'overall').to_s.downcase
  event << "#{player.name} has #{points} #{type} points."
end

def send_diff(event)
  type = parse_type(event.content) || Level
  current = get_current(type)
  old_scores = get_saved_scores(type)
  since = type == Level ? "yesterday" : "last week"

  diff = current.format_difference(old_scores)
  $channel.send_message("Score changes on #{current.format_name} since #{since}:\n```#{diff}```")
end

def identify(event)
  msg = event.content
  user = event.user.name
  nick = msg[/my name is (.*)[\.]?$/i, 1]

  raise "I couldn't figure out who you were! You have to send a message in the form 'my name is <username>.'" if nick.nil?

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
  next_level = get_next_update(Level) - Time.now
  next_level_hours = (next_level / (60 * 60)).to_i
  next_level_minutes = (next_level / 60).to_i - (next_level / (60 * 60)).to_i * 60

  event << "I'll post a new level of the day in #{next_level_hours} hours and #{next_level_minutes} minutes."
end

def send_episode_time(event)
  next_episode = get_next_update(Episode) - Time.now

  next_episode_days = (next_episode / (24 * 60 * 60)).to_i
  next_episode_hours = (next_episode / (60 * 60)).to_i - (next_episode / (24 * 60 * 60)).to_i * 24

  event << "I'll post a new episode of the week in #{next_episode_days} days and #{next_episode_hours} hours."
end

def send_times(event)
  send_level_time(event)
  send_episode_time(event)
end

def send_help(event)
  event << "The commands I understand are:"

  File.open('README.md').read.each_line do |line|
    line = line.gsub("\n", "")
    event << "\n**#{line.gsub(/^### /, "")}**" if line =~ /^### /
    event << " *#{line.gsub(/^- /, "").gsub(/\*/, "")}*" if line =~ /^- \*/
  end
end

def send_level(event)
  event << "The current level of the day is #{get_current(Level).format_name}."
end

def send_episode(event)
  event << "The current episode of the week is #{get_current(Episode).format_name}."
end

def dump(event)
  log("current level/episode: #{get_current(Level).format_name}, #{get_current(Episode).format_name}") unless get_current(Level).nil?
  log("next updates: scores #{get_next_update('score')}, level #{get_next_update(Level)}, episode #{get_next_update(Episode)}")

  event << "I dumped some things to the log for you to look at."
end

def download_high_scores
  ActiveRecord::Base.establish_connection(CONFIG)

  while true
    log("updating high scores...")

    Level.all.each(&:download_scores)
    Episode.all.each(&:download_scores)

    next_score_update = get_next_update('score')
    next_score_update += HIGHSCORE_UPDATE_FREQUENCY
    delay = next_score_update - Time.now
    set_next_update('score', next_score_update)

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
  $channel.send_message("Score changes on #{level.format_name} since #{since}:\n```#{diff}```")
end

def send_channel_next(type)
  $lock.synchronize do
    log("sending next #{type.to_s.downcase}")
    if $channel.nil?
      err("not connected to a channel, not sending level of the day")
      return false
    end

    last = get_current(type)
    current = get_next(type)
    set_current(type, current)

    if current.nil?
      err("no more #{type.to_s.downcase}")
      return false
    end

    prefix = type == Level ? "Time" : "It's also time"
    duration = type == Level ? "day" : "week"
    time = type == Level ? "today" : "this week"
    since = type == Level ? "yesterday" : "last week"
    typename = type.to_s.downcase

    caption = "#{prefix} for a new #{typename} of the #{duration}! The #{typename} for #{time} is #{current.format_name}."
    send_channel_screenshot(current.name, caption)
    $channel.send_message("Current high scores:\n```#{current.format_scores}```")

    send_channel_diff(last, get_saved_scores(type), since)
    set_saved_scores(type, current)

    return true
  end
end

def start_level_of_the_day
  log("starting level of the day...")
  while true
    next_level_update = get_next_update(Level)
    sleep(next_level_update - Time.now) unless next_level_update - Time.now < 0
    set_next_update(Level, next_level_update + LEVEL_UPDATE_FREQUENCY)

    next if !send_channel_next(Level)
    log("sent next level, next update at #{get_next_update(Level).to_s}")

    next_episode_update = get_next_update(Episode)
    if Time.now > next_episode_update
      set_next_update(Episode, next_episode_update + EPISODE_UPDATE_FREQUENCY)

      sleep(30) # let discord catch up

      send_channel_next(Episode)
      log("sent next episode, next update at #{get_next_update(Episode).to_s}")
    end
  end
rescue RuntimeError => e
  err("error updating level of the day: #{e}")
end

def startup
  ActiveRecord::Base.establish_connection(CONFIG)

  log("initialized")
  log("next level update at #{get_next_update(Level).to_s}")
  log("next episode update at #{get_next_update(Episode).to_s}")
  log("next score update at #{get_next_update('score')}")
end

def shutdown
  log("shutting down")
  $bot.stop
end

def watchdog
  sleep(3) while !$kill_threads
  shutdown
end

# TODO set level of the day on startup
def respond(event)
  hello(event) if event.content =~ /\bhello\b/i || event.content =~ /\bhi\b/i
  dump(event) if event.content =~ /dump/i
  send_episode_time(event) if event.content =~ /when.*next.*(episode|eotw)/i
  send_level_time(event) if  event.content =~ /when.*next.*(level|lotd)/i
  send_level(event) if event.content =~ /what.*(level|lotd)/i
  send_episode(event) if event.content =~ /what.*(episode|eotw)/i
  send_rankings(event) if event.content =~ /rank/i
  send_points(event) if event.content =~ /points/i && event.content !~ /rank/i
  send_top_n_count(event) if event.content =~ /how many/i
  send_stats(event) if event.content =~ /stat/i
  send_spreads(event) if event.content =~ /spread/i
  send_screenshot(event) if event.content =~ /screenshot/i
  send_scores(event) if event.content =~ /scores/i
  send_suggestions(event) if event.content =~ /worst/i
  send_list(event) if event.content =~ /list/i
  send_missing(event) if event.content =~ /missing/i
  send_level_name(event) if event.content =~ /\blevel name\b/i
  send_level_id(event) if event.content =~ /\blevel id\b/i
  send_diff(event) if event.content =~ /diff/i
  send_help(event) if event.content =~ /\bhelp\b/i || event.content =~ /\bcommands\b/i
  identify(event) if event.content =~ /my name is/i
rescue RuntimeError => e
  event << e
end

$bot = Discordrb::Bot.new token: CONFIG['token'], client_id: CONFIG['client_id']
$channel = nil

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
  # Thread.new { start_level_of_the_day },
  Thread.new { download_high_scores },
]

$bot.run(true)

wd = Thread.new { watchdog }
wd.join
