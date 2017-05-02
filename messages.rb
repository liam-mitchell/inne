require 'ascii_charts'
require_relative 'models.rb'

LEVEL_PATTERN = /S[ILU]?-[ABCDEX]-[0-9][0-9]?-[0-9][0-9]?|[?!]-[ABCDE]-[0-9][0-9]?/i
EPISODE_PATTERN = /S[ILU]?-[ABCDEX]-[0-9][0-9]?/i
NAME_PATTERN = /(for|of) (.*)[\.\?]?/i

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

def parse_rank(msg)
  rank = msg[/top\s*([0-9][0-9]?)/i, 1]
  rank ? rank.to_i : nil
end

def parse_tab(msg)
  ret = []

  ret << 'SI' if msg =~ /\b(intro|SI|I)\b/i
  ret << 'S' if msg =~ /(\b|\A|\s)(N++|S|solo)(\b|\Z|\s)/i
  ret << 'SU' if msg =~ /\b(SU|UE|U|ultimate)\b/i
  ret << 'SL' if msg =~ /\b(legacy|SL|L)\b/i
  ret << '!' if msg =~ /(\b|\A|\s)(ultimate secret|!)(\b|\Z|\s)/i
  ret << '?' if msg =~ /(\b|\A|\s)(secret|\?)(\b|\Z|\s)/i

  ret
end

def send_top_n_count(event)
  msg = event.content
  player = parse_player(msg, event.user.name)
  n = parse_rank(msg) || 1
  type = parse_type(msg)
  tab = parse_tab(msg)
  ties = !!(msg =~ /ties/i)

  count = player.top_n_count(n, type, tab, ties)

  header = (n == 1 ? "0th" : "top #{n}")
  type = (type || 'overall').to_s.downcase
  tab = tab.to_sentence + (tab.empty? ? "" : " ")

  event << "#{player.name} has #{count} #{type} #{header} #{tab}scores#{ties ? " with ties" : ""}."
end

def send_rankings(event)
  msg = event.content
  type = parse_type(msg)
  tab = parse_tab(msg)
  n = parse_rank(msg) || 1
  ties = !!(msg =~ /ties/i)

  if msg =~ /point/
    rankings = Player.rankings { |p| p.points(type, tab) }
    header = "point rankings "
    format = "%d"
  elsif msg =~ /score/
    rankings = Player.rankings { |p| p.total_score(type, tab) }
    header = "score rankings "
    format = "%.3f"
  else
    rankings = Player.rankings { |p| p.top_n_count(n, type, tab, ties) }

    rank = (n == 1 ? "0th" : "top #{n}")
    ties = (ties ? "with ties " : "")

    header = "#{rank} rankings #{ties}"
    format = "%d"
  end

  type = (type || "Overall").to_s
  tab = tab.to_sentence + (tab.empty? ? "" : " ")

  top = rankings.take(20).each_with_index.map { |r, i| "#{HighScore.format_rank(i)}: #{r[0].name} (#{format % r[1]})" }
        .join("\n")

  event << "#{type} #{tab}#{header}#{Time.now.strftime("on %A %B %-d at %H:%M:%S (%z)")}:\n```#{top}```"
end

def send_total_score(event)
  player = parse_player(event.content, event.user.name)
  type = parse_type(event.content)
  tab = parse_tab(event.content)

  score = player.total_score(type, tab)

  type = (type || 'overall').to_s.downcase
  tab = tab.to_sentence + (tab.empty? ? "" : " ")

  event << "#{player.name}'s total #{tab}#{type.to_s.downcase} score is #{score}."
end

def send_spreads(event)
  msg = event.content
  n = (msg[/([0-9][0-9]?)(st|nd|th)/, 1] || 1).to_i
  type = parse_type(msg) || Level
  tab = parse_tab(msg)
  smallest = !!(msg =~ /smallest/)

  if n == 0
    event << "I can't show you the spread between 0th and 0th..."
    return
  end

  spreads = HighScore.spreads(n, type, tab)
            .sort_by { |level, spread| (smallest ? spread : -spread) }
            .take(20)
            .map { |s| "#{s[0]} (#{"%.3f" % [s[1]]})"}
            .join("\n\t")

  spread = smallest ? "smallest" : "largest"
  rank = (n == 1 ? "1st" : (n == 2 ? "2nd" : (n == 3 ? "3rd" : "#{n}th")))
  tab = tab.to_sentence + (tab.empty? ? "" : " ")
  type = type.to_s
  type = tab.empty? ? tab : type.downcase

  event << "#{tab}#{type}s with the #{spread} spread between 0th and #{rank}:\n\t#{spreads}"
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
  msg = event.content
  player = parse_player(msg, event.user.name)
  tab = parse_tab(msg)
  counts = player.score_counts(tab)

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

  tab = tab.empty? ? " in the #{tab.to_sentence} #{tab.length == 1 ? 'tab' : 'tabs'}" : ''

  event << "Player high score counts for #{player.name}#{tab}:\n```\t    Overall:\tLevel:\tEpisode:\n\t#{totals}\n#{overall}"
  event << "#{histogram}```"
end

def send_list(event)
  msg = event.content
  player = parse_player(msg, event.user.name)
  type = parse_type(msg)
  tab = parse_tab(msg)
  all = player.scores_by_rank(type, tab)

  tmpfile = File.join(Dir.tmpdir, "scores-#{player.name.delete(":")}.txt")
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
end

def send_missing(event)
  msg = event.content
  player = parse_player(msg, event.user.name)
  type = parse_type(msg)
  tab = parse_tab(msg)
  rank = parse_rank(msg) || 20
  ties = !!(msg =~ /ties/i)

  missing = player.missing_top_ns(rank, type, tab, ties).join("\n")

  tmpfile = File.join(Dir.tmpdir, "missing-#{player.name.delete(":")}.txt")
  File::open(tmpfile, "w") do |f|
    f.write(missing)
  end

  event.attach_file(File::open(tmpfile))
end

def send_suggestions(event)
  msg = event.content
  player = parse_player(msg, event.user.name)
  type = parse_type(msg) || Level
  tab = parse_tab(msg)
  n = (msg[/\b[0-9][0-9]?\b/] || 10).to_i

  improvable = player.improvable_scores(type, tab)
               .sort_by { |level, gap| -gap }
               .take(n)
               .map { |level, gap| "#{level} (-#{"%.3f" % [gap]})" }
               .join("\n")

  missing = player.missing_top_ns(20, type, tab, false).sample(n).join("\n")
  type = type.to_s.downcase
  tab = tab.empty? ? " in the #{tab.to_sentence} #{tab.length == 1 ? 'tab' : 'tabs'}" : ''

  event << "Your #{n} most improvable #{type}s#{tab} are:\n```#{improvable}```"
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
  tab = parse_tab(msg)
  points = player.points(type, tab)

  type = (type || 'overall').to_s.downcase
  tab = tab.to_sentence + (tab.empty? ? "" : " ")
  event << "#{player.name} has #{points} #{type} #{tab}points."
end

def send_diff(event)
  type = parse_type(event.content) || Level
  current = get_current(type)
  old_scores = get_saved_scores(type)
  since = type == Level ? "yesterday" : "last week"

  diff = current.format_difference(old_scores)
  event << "Score changes on #{current.format_name} since #{since}:\n```#{diff}```"
end

def identify(event)
  msg = event.content
  user = event.user.name
  nick = msg[/my name is (.*)[\.]?$/i, 1]

  raise "I couldn't figure out who you were! You have to send a message in the form 'my name is <username>.'" if nick.nil?

  player = Player.find_or_create_by(name: nick)
  user = User.find_or_create_by(username: user)
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

# TODO set level of the day on startup
def respond(event)
  msg = event.content

  hello(event) if msg =~ /\bhello\b/i || msg =~ /\bhi\b/i
  dump(event) if msg =~ /dump/i
  send_episode_time(event) if msg =~ /when.*next.*(episode|eotw)/i
  send_level_time(event) if  msg =~ /when.*next.*(level|lotd)/i
  send_level(event) if msg =~ /what.*(level|lotd)/i
  send_episode(event) if msg =~ /what.*(episode|eotw)/i
  send_rankings(event) if msg =~ /rank/i
  send_points(event) if msg =~ /points/i && msg !~ /rank/i
  send_top_n_count(event) if msg =~ /how many/i
  send_stats(event) if msg =~ /stat/i
  send_spreads(event) if msg =~ /spread/i
  send_screenshot(event) if msg =~ /screenshot/i
  send_scores(event) if msg =~ /scores/i
  send_suggestions(event) if msg =~ /worst/i
  send_list(event) if msg =~ /list/i
  send_missing(event) if msg =~ /missing/i
  send_level_name(event) if msg =~ /\blevel name\b/i
  send_level_id(event) if msg =~ /\blevel id\b/i
  send_diff(event) if msg =~ /diff/i
  send_help(event) if msg =~ /\bhelp\b/i || msg =~ /\bcommands\b/i
  identify(event) if msg =~ /my name is/i
rescue RuntimeError => e
  event << e
end
