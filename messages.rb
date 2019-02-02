require 'ascii_charts'
require 'gruff'
require_relative 'models.rb'

LEVEL_PATTERN = /S[ILU]?-[ABCDEX]-[0-9][0-9]?-[0-9][0-9]?|[?!]-[ABCDE]-[0-9][0-9]?/i
EPISODE_PATTERN = /S[ILU]?-[ABCDEX]-[0-9][0-9]?/i
NAME_PATTERN = /(for|of) (.*)[\.\?]?/i

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

def parse_steam_id(msg)
  id = msg[/is (.*)[\.\?]?/i, 1]
  raise "I couldn't figure out what your Steam ID was! You need to send a message in the format 'my steam id is <id>'." if id.nil?
  raise "Your Steam ID needs to be numerical! #{id} is not valid." if id !~ /\A\d+\Z/
  return id
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
  elsif !msg[/(level of the day|lotd)/].nil?
    ret = get_current(Level)
  elsif !msg[/(episode of the week|eotw)/].nil?
    ret = get_current(Episode)
  elsif name
    ret = Level.find_by("UPPER(longname) LIKE ?", name.upcase)
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

def parse_bottom_rank(msg)
  rank = msg[/bottom\s*([0-9][0-9]?)/i, 1]
  rank ? 20 - rank.to_i : nil
end

def parse_tabs(msg)
  ret = []

  ret << :SI if msg =~ /\b(intro|SI|I)\b/i
  ret << :S if msg =~ /(\b|\A|\s)(N++|S|solo)(\b|\Z|\s)/i
  ret << :SU if msg =~ /\b(SU|UE|U|ultimate)\b/i
  ret << :SL if msg =~ /\b(legacy|SL|L)\b/i
  ret << :SS if msg =~ /(\A|\s)(secret|\?)(\Z|\s)/i
  ret << :SS2 if msg =~ /(\A|\s)(ultimate secret|!)(\Z|\s)/i

  ret
end

def format_rank(rank)
  rank == 1 ? "0th" : "top #{rank}"
end

def format_type(type)
  (type || 'Overall').to_s
end

def format_ties(ties)
  ties ? "with ties " : ""
end

def format_tab(tab)
  (tab == :SS2 ? '!' : (tab == :SS ? '?' : tab.to_s))
end

def format_tabs(tabs)
  tabs.map { |t| format_tab(t) }.to_sentence + (tabs.empty? ? "" : " ")
end

def format_time
  Time.now.strftime("on %A %B %-d at %H:%M:%S (%z)")
end

def send_top_n_count(event)
  msg = event.content
  player = parse_player(msg, event.user.name)
  rank = parse_rank(msg) || 1
  type = parse_type(msg)
  tabs = parse_tabs(msg)
  ties = !!(msg =~ /ties/i)

  count = player.top_n_count(rank, type, tabs, ties)

  header = format_rank(rank)
  type = format_type(type).downcase
  tabs = format_tabs(tabs)
  ties = format_ties(ties)

  event << "#{player.name} has #{count} #{tabs}#{type} #{header} scores#{ties}."
end

def send_rankings(event)
  msg = event.content
  type = parse_type(msg)
  tabs = parse_tabs(msg)
  rank = parse_rank(msg) || 1
  ties = !!(msg =~ /ties/i)

  if msg =~ /average/i
    if msg =~ /point/i
      players = Player.where(id: Player.joins(:scores).group('players.id').having('count(highscoreable_id) > 50').pluck(:id))
      rankings = players.rankings { |p| p.average_points(type, tabs) }
      header = "average point rankings "
      format = "%.3f"
    else
      players = Player.where(id: Player.joins(:scores).group('players.id').having('count(highscoreable_id) > 50').pluck(:id))
      rankings = players.rankings { |p| p.average_points(type, tabs) }.map{|p| [p[0], 20-p[1]] }
      header = "average rank rankings "
      format = "%.3fth"
    end
  elsif msg =~ /point/i
    rankings = Player.rankings { |p| p.points(type, tabs) }
    header = "point rankings "
    format = "%d"
  elsif msg =~ /score/i
    rankings = Player.rankings { |p| p.total_score(type, tabs) }
    header = "score rankings "
    format = "%.3f"
  elsif msg =~ /tied/i
    rankings = Player.rankings { |p| p.top_n_count(1, type, tabs, true) - p.top_n_count(1, type, tabs, false) }
    header = "tied 0th rankings "
    format = "%d"
  else
    rankings = Player.rankings { |p| p.top_n_count(rank, type, tabs, ties) }
    rank = format_rank(rank)
    ties = (ties ? "with ties " : "")
    header = "#{rank} rankings #{ties}"
    format = "%d"
  end

  type = format_type(type)
  tabs = format_tabs(tabs)

  top = rankings.take(20).select { |r| r[1] > 0 }.each_with_index.map { |r, i| "#{HighScore.format_rank(i)}: #{r[0].name} (#{format % r[1]})" }
        .join("\n")

  event << "#{type} #{tabs}#{header}#{format_time}:\n```#{top}```"
end

def send_total_score(event)
  player = parse_player(event.content, event.user.name)
  type = parse_type(event.content)
  tabs = parse_tabs(event.content)

  score = player.total_score(type, tabs)

  type = format_type(type).downcase
  tabs = format_tabs(tabs)

  event << "#{player.name}'s total #{tabs}#{type.to_s.downcase} score is #{"%.3f" % [score]}."
end

def send_spreads(event)
  msg = event.content
  n = (msg[/([0-9][0-9]?)(st|nd|th)/, 1] || 1).to_i
  type = parse_type(msg) || Level
  tabs = parse_tabs(msg)
  smallest = !!(msg =~ /smallest/)

  if n == 0
    event << "I can't show you the spread between 0th and 0th..."
    return
  end

  spreads = HighScore.spreads(n, type, tabs)
            .sort_by { |level, spread| (smallest ? spread : -spread) }
            .take(20)
            .map { |s| "#{s[0]} (#{"%.3f" % [s[1]]})"}
            .join("\n\t")

  spread = smallest ? "smallest" : "largest"
  rank = (n == 1 ? "1st" : (n == 2 ? "2nd" : (n == 3 ? "3rd" : "#{n}th")))
  type = format_type(type).downcase
  tabs = tabs.empty? ? "All " : format_tabs(tabs)

  event << "#{tabs}#{type}s with the #{spread} spread between 0th and #{rank}:\n\t#{spreads}"
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
    Level.where("UPPER(name) LIKE ?", scores.name.upcase + '%').each(&:download_scores)
  end
end

def send_screenshot(event)
  msg = event.content
  scores = parse_level_or_episode(msg)
  name = scores.name.upcase.gsub(/\?/, 'SS').gsub(/!/, 'SS2')

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
  tabs = parse_tabs(msg)
  counts = player.score_counts(tabs)

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

  tabs = tabs.empty? ? "" : " in the #{format_tabs(tabs)} #{tabs.length == 1 ? 'tab' : 'tabs'}"

  event << "Player high score counts for #{player.name}#{tabs}:\n```\t    Overall:\tLevel:\tEpisode:\n\t#{totals}\n#{overall}"
  event << "#{histogram}```"
end

def send_list(event)
  msg = event.content
  player = parse_player(msg, event.user.name)
  type = parse_type(msg)
  tabs = parse_tabs(msg)
  rank = parse_rank(msg) || 20
  bott = parse_bottom_rank(msg) || 0
  ties = !!(msg =~ /ties/i)
  all = player.scores_by_rank(type, tabs)

  if rank == 20 && bott == 0 && !!msg[/0th/i]
    rank = 1
    bott = 0
  end

  tmpfile = File.join(Dir.tmpdir, "scores-#{player.name.delete(":")}.txt")
  File::open(tmpfile, "w", crlf_newline: true) do |f|
    all[bott..rank-1].each_with_index do |scores, i|
      list = scores.map { |s| "#{HighScore.format_rank(s.rank)}: #{s.highscoreable.name} (#{"%.3f" % [s.score]})" }
             .join("\n  ")
      f.write("#{bott+i}:\n  ")
      f.write(list)
      f.write("\n")
    end
  end

  event.attach_file(File::open(tmpfile))
end

def send_community(event)
  msg = event.content
  tabs = parse_tabs(msg)
  condition = !(tabs&[:SS, :SS2]).empty? || tabs.empty?
  text = ""

  levels = Score.total_scores(Level, tabs, true)
  episodes = Score.total_scores(Episode, tabs, false)
  levels_no_secrets = (condition ? Score.total_scores(Level, tabs, false) : levels)
  difference = levels_no_secrets[0] - 4 * 90 * episodes[1] - episodes[0]
  # For every episode, we subtract the additional 90 seconds
  # 4 of the 5 individual levels give you at the start to be able
  # to compare an episode score with the sum of its level scores.

  text << "Total level score: #{levels[0]}\n"
  text << "Total episode score: #{episodes[0]}\n"
  text << (condition ? "Total level score (w/o secrets): #{levels_no_secrets[0]}\n" : "")
  text << "Difference between level and episode 0ths: #{"%.3f" % [difference]}\n\n"
  text << "Average level score: #{"%.3f" % [levels[0]/levels[1]]}\n"
  text << "Average episode score: #{"%.3f" % [episodes[0]/episodes[1]]}\n"
  text << "Average difference between level and episode 0ths: #{"%.3f" % [difference/episodes[1]]}\n"

  event << "Community's total #{format_tabs(tabs)}scores #{format_time}:\n```#{text}```"
end

def send_maxable(event)
  msg = event.content
  type = parse_type(msg) || Level
  tabs = parse_tabs(msg)

  ties = HighScore.ties(type, tabs)
            .select { |level, tie| tie < 20 }
            .sort_by { |level, tie| -tie }
            .take(20)
            .map { |s| "#{s[0]} (#{s[1]})" }
            .join("\n")

  type = format_type(type).downcase
  tabs = tabs.empty? ? "All " : format_tabs(tabs)

  event << "#{tabs}#{type}s with the most ties for 0th #{format_time}:\n```#{ties}```"
end

def send_maxed(event)
  msg = event.content
  type = parse_type(msg) || Level
  tabs = parse_tabs(msg)

  ties = HighScore.ties(type, tabs)
            .select { |level, tie| tie == 20 }
            .map { |s| "#{s[0]}\n" }
  ties_list = ties.join

  type = format_type(type).downcase
  tabs = tabs.empty? ? "All " : format_tabs(tabs)

  event << "#{tabs}potentially maxed #{type}s (with at least 20 ties for 0th) #{format_time}:\n```#{ties_list}```There's a total of #{ties.count{|s| s.length>1}} potentially maxed #{type}s."
end

def send_cleanliness(event)
  msg = event.content
  tabs = parse_tabs(msg)
  cleanest = !!msg[/cleanest/i]
  episodes = tabs.empty? ? Episode.all : Episode.where(tab: tabs)

  cleanliness = episodes.map{ |e| e.cleanliness }
                .sort_by{ |e| (cleanest ? e[1] : -e[1]) }
                .map{ |e| "#{e[0]}:#{e[0][1] == '-' ? "  " : " "}%.3f" % [e[1]] }
                .take(20)
                .join("\n")

  tabs = tabs.empty? ? "All " : format_tabs(tabs)
  event << "#{tabs}#{cleanest ? "cleanest" : "dirtiest"} episodes #{format_time}:\n```#{cleanliness}```"
end

def send_ownages(event)
  msg = event.content
  tabs = parse_tabs(msg)
  ties = !!(msg =~ /ties/i)
  episodes = tabs.empty? ? Episode.all : Episode.where(tab: tabs)

  ownages = episodes.map{ |e| e.ownage }
            .select{ |e| e[1] == true }
            .map{ |e| "#{e[0]}:#{e[0][1]=='-' ? "  " : " "}#{e[2]}" }
  ownages_list = ownages.join("\n")

  tabs = tabs.empty? ? "All " : format_tabs(tabs)
  event << "#{tabs}episode ownages #{format_time}:\n```#{ownages_list}```There's a total of #{ownages.count} episode ownages."
end

def send_missing(event)
  msg = event.content
  player = parse_player(msg, event.user.name)
  type = parse_type(msg)
  tabs = parse_tabs(msg)
  rank = parse_rank(msg) || 20
  ties = !!(msg =~ /ties/i)

  missing = player.missing_top_ns(rank, type, tabs, ties).join("\n")

  tmpfile = File.join(Dir.tmpdir, "missing-#{player.name.delete(":")}.txt")
  File::open(tmpfile, "w", crlf_newline: true) do |f|
    f.write(missing)
  end

  event.attach_file(File::open(tmpfile))
end

def send_suggestions(event)
  msg = event.content
  player = parse_player(msg, event.user.name)
  type = parse_type(msg) || Level
  tabs = parse_tabs(msg)
  n = (msg[/\b[0-9][0-9]?\b/] || 10).to_i

  improvable = player.improvable_scores(type, tabs)
               .sort_by { |level, gap| -gap }
               .take(n)
               .map { |level, gap| "#{level} (-#{"%.3f" % [gap]})" }
               .join("\n")

  missing = player.missing_top_ns(20, type, tabs, false).sample(n).join("\n")
  type = type.to_s.downcase
  tabs = tabs.empty? ? "" :  " in the #{format_tabs(tabs)} #{tabs.length == 1 ? 'tab' : 'tabs'}"

  event << "Your #{n} most improvable #{type}s#{tabs} are:\n```#{improvable}```"
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
  tabs = parse_tabs(msg)
  points = player.points(type, tabs)

  type = format_type(type).downcase
  tabs = format_tabs(tabs)
  event << "#{player.name} has #{points} #{type} #{tabs}points."
end

def send_average_points(event)
  msg = event.content
  player = parse_player(msg, event.user.name)
  type = parse_type(msg)
  tabs = parse_tabs(msg)
  average = player.average_points(type, tabs)

  type = format_type(type).downcase
  tabs = format_tabs(tabs)
  event << "#{player.name} has #{"%.3f" % [average]} #{type} #{tabs}average points."
end

def send_diff(event)
  type = parse_type(event.content) || Level
  current = get_current(type)
  old_scores = get_saved_scores(type)
  since = type == Level ? "yesterday" : "last week"

  diff = current.format_difference(old_scores)
  event << "Score changes on #{current.format_name} since #{since}:\n```#{diff}```"
end

def send_history(event)
  msg = event.content

  type = parse_type(msg)
  tabs = parse_tabs(msg)
  rank = parse_rank(msg) || 1
  ties = !!(msg =~ /ties/i)

  if msg =~ /point/
    history = Player.points_histories(type, tabs)
    header = "point "
  elsif msg =~ /score/
    history = Player.score_histories(type, tabs)
    header = "score "
  else
    history = Player.rank_histories(rank, type, tabs, ties)
    header = format_rank(rank) + " " + format_ties(ties)
  end

  history = history.sort_by { |player, data| data.max_by { |k, v| v }[1] }
            .reverse
            .take(30)
            .select { |player, data| data.any? { |k, v| v > rank * 2 * tabs.length } }

  type = format_type(type)
  tabs = format_tabs(tabs)

  graph = Gruff::Line.new(1280, 2000)
  graph.title = "#{type} #{tabs}#{header}history"
  graph.theme_pastel
  graph.colors = []
  graph.legend_font_size = 10
  graph.marker_font_size = 10
  graph.legend_box_size = 10
  graph.line_width = 1
  graph.hide_dots = true

  step = Math.cbrt(history.count).ceil
  step.times do |i|
    step.times do |j|
      step.times do |k|
        scale = 0xFF / (step - 1)
        colour = ((scale * i) << 16) + ((scale * j) << 8) + (scale * k)
        graph.add_color("##{"%06x" % [colour]}")
      end
    end
  end

  graph.colors = graph.colors.shuffle

  history.each { |player, data| graph.dataxy(player, data.keys, data.values) }

  tmpfile = File.join(Dir.tmpdir, "history.png")
  graph.write(tmpfile)

  event.attach_file(File.open(tmpfile))
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

def add_steam_id(event)
  msg = event.content
  id = parse_steam_id(msg)
  User.find_by(username: event.user.name)
    .update(steam_id: id)
  event << "Thanks! From now on I'll try to use your Steam ID to retrieve scores when I need to."
end

def hello(event)
  event << "Hi!"

  if $channel.nil?
    $channel = event.channel
    send_times(event)
  end
end

def thanks(event)
  event << "You're welcome!"
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
  # event << "The commands I understand are:"
  msg = "The commands I understand are:\n"

  File.open('README.md').read.each_line do |line|
    line = line.gsub("\n", "")
    if line == " "
      event.send_message(msg)
      msg = "Commands continued...\n"
    else
      msg += "\n**#{line.gsub(/^### /, "")}**\n" if line =~ /^### /
      msg += " *#{line.gsub(/^- /, "").gsub(/\*/, "")}*\n" if line =~ /^- \*/
    end
  end

  event.send_message(msg)

  event << "In any of these commands, if you see '<level>', replace that with either a level/episode ID (eg. SI-A-00-00) or a level name (eg. supercomplexity)"
  event << "If you see '<tab>', you can replace that with any combination of SI/intro, S/N++, SU/ultimate, SL/legacy, ?/secret, and !/ultimate secret, or you can leave it off for overall totals."
  event << "If the command is related to a specific player, you can specify it by ending your message with 'for <username>'. Otherwise, I'll use the one you specified earlier."
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

  # strip off the @inne++ mention, if present
  msg.sub!(/\A<@[0-9]*> */, '')

  # match exactly "lotd" or "eotw", regardless of capitalization or leading/trailing whitespace
  if msg =~ /\A\s*lotd\s*\Z/i
    send_level(event)
    return
  elsif msg =~ /\A\s*eotw\s*\Z/i
    send_episode(event)
    return
  end

  # exclusively global methods, this conditional avoids the problem stated in the comment below
  if !msg[NAME_PATTERN, 2]
    send_rankings(event) if msg =~ /rank/i && msg !~ /history/i
    send_history(event) if msg =~ /history/i && msg !~ /rank/i
    send_spreads(event) if msg =~ /spread/i
    send_diff(event) if msg =~ /diff/i
    send_community(event) if msg =~ /community/i
    send_maxable(event) if msg =~ /maxable/i
    send_maxed(event) if msg =~ /maxed/i
    send_cleanliness(event) if msg =~ /cleanest/i || msg =~ /dirtiest/i
    send_ownages(event) if msg =~ /ownage/i
    send_help(event) if msg =~ /\bhelp\b/i || msg =~ /\bcommands\b/i
  end

  # on this methods, we will exclude a few problematic words that appear
  # in some level names which would accidentally trigger them
  hello(event) if msg =~ /\bhello\b/i || msg =~ /\bhi\b/i
  thanks(event) if msg =~ /\bthank you\b/i || msg =~ /\bthanks\b/i
  dump(event) if msg =~ /dump/i
  send_level(event) if msg =~ /what.*(level|lotd)/i
  send_episode(event) if msg =~ /what.*(episode|eotw)/i
  send_episode_time(event) if msg =~ /when.*next.*(episode|eotw)/i
  send_level_time(event) if  msg =~ /when.*next.*(level|lotd)/i
  send_points(event) if msg =~ /\bpoints/i && msg !~ /history/i && msg !~ /rank/i && msg !~ /average/i && msg !~ /floating/i && msg !~ /legrange/i
  send_average_points(event) if msg =~ /\bpoints/i && msg !~ /history/i && msg !~ /rank/i && msg =~ /average/i && msg !~ /floating/i && msg !~ /legrange/i
  send_scores(event) if msg =~ /scores/i && msg !~ /history/i && msg !~ /rank/i
  send_total_score(event) if msg =~ /\btotal/i && msg !~ /history/i && msg !~ /rank/i
  send_top_n_count(event) if msg =~ /how many/i
  send_stats(event) if msg =~ /\bstat/i && msg !~ /generator/i && msg !~ /hooligan/i && msg !~ /space station/i
  send_screenshot(event) if msg =~ /screenshot/i
  send_suggestions(event) if msg =~ /worst/i && msg !~ /nightmare/i
  send_list(event) if msg =~ /\blist\b/i && msg !~ /of inappropriate words/i
  send_missing(event) if msg =~ /missing/i
  send_level_name(event) if msg =~ /\blevel name\b/i
  send_level_id(event) if msg =~ /\blevel id\b/i
  identify(event) if msg =~ /my name is/i
  add_steam_id(event) if msg =~ /my steam id is/i

rescue RuntimeError => e
  event << e
end
