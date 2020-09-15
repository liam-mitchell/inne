require 'ascii_charts'
require 'gruff'
require 'zlib'
require_relative 'models.rb'
require_relative 'userlevels.rb'

LEVEL_PATTERN   = /S[ILU]?-[ABCDEX]-[0-9][0-9]?-[0-9][0-9]?|[?!]-[ABCDE]-[0-9][0-9]?/i
EPISODE_PATTERN = /S[ILU]?-[ABCDEX]-[0-9][0-9]?/i
STORY_PATTERN   = /S[ILU]?-[0-9][0-9]?/i
NAME_PATTERN    = /(for|of) (.*)[\.\?]?/i

NUM_ENTRIES = 20 # number of entries to show on diverse methods
MAX_ENTRIES = 20 # maximum number of entries on methods with user input, to avoid spam
MIN_SCORES  = 50  # minimum number of highscores to appear in average point rankings

# userlevel functions
PAGE_SIZE = 20

def parse_type(msg)
  (msg[/level/i] ? Level : (msg[/episode/i] ? Episode : ((msg[/\bstory\b/i] || msg[/\bcolumn/i] || msg[/hard\s*core/i] || msg[/\bhc\b/i]) ? Story : nil)))
end

def normalize_name(name)
  name.split('-').map { |s| s[/\A[0-9]\Z/].nil? ? s : "0#{s}" }.join('-').upcase
end

def parse_player(msg, username)
  p = msg[/for (.*)[\.\?]?/i, 1]

  # We make sure to only return players with metanet_ids, ie., with highscores.
  if p.nil?
    raise "I couldn't find a player with your username! Have you identified yourself (with '@outte++ my name is <N++ display name>')?" unless User.exists?(username: username)
    player = Player.where.not(metanet_id: nil).find_by(name: User.find_by(username: username).player.name)
    raise "#{p} doesn't have any high scores! Either you misspelled the name, or they're exceptionally bad..." unless !player.nil?
    player
  else
    player = Player.where.not(metanet_id: nil).find_by(name: p)
    raise "#{p} doesn't have any high scores! Either you misspelled the name, or they're exceptionally bad..." unless !player.nil?
    player
  end
end

def parse_video_author(msg)
  return msg[/by (.*)[\.\?]?\Z/i, 1]
end

def parse_challenge(msg)
  return msg[/([GTOCE][+-][+-])+/]
end

def parse_challenge_code(msg)
  return msg[/([!?]+)[^-]/, 1]
end

def parse_videos(msg)
  author = parse_video_author(msg)
  msg = msg.chomp(" by " + author.to_s)
  highscoreable = parse_level_or_episode(msg)
  challenge = parse_challenge(msg)
  code = parse_challenge_code(msg)
  videos = highscoreable.videos

  videos = videos.where('lower(author) = ? or lower(author_tag) = ?', author.downcase, author.downcase) unless author.nil?
  videos = videos.where(challenge: challenge) unless challenge.nil?
  videos = videos.where(challenge_code: code) unless code.nil?

  raise "That level doesn't have any videos!" if highscoreable.videos.empty?
  raise "I couldn't find any videos matching that request! Are you looking for one of these videos?\n```#{highscoreable.videos.map(&:format_description).join("\n")}```" if videos.empty?
  return videos
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
  story = msg[STORY_PATTERN]
  name = msg[NAME_PATTERN, 2]
  ret = nil

  if level
    ret = Level.find_by(name: normalize_name(level).upcase)
  elsif episode
    ret = Episode.find_by(name: normalize_name(episode).upcase)
  elsif story
    ret = Story.find_by(name: normalize_name(story).upcase)
  elsif !msg[/(level of the day|lotd)/].nil?
    ret = get_current(Level)
  elsif !msg[/(episode of the week|eotw)/].nil?
    ret = get_current(Episode)
  elsif name
    ret = Level.find_by("UPPER(longname) LIKE ?", name.upcase)
  else
    msg = "I couldn't figure out which level, episode or column you wanted scores for! You need to send either a level, " +
          "an episode or a column ID that looks like SI-A-00-00, SI-A-00 or SI-00; or a level name, using 'for <name>.'"
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

def parse_ranks(msg)
  ranks = msg.scan(/\s+([0-9][0-9]?)/).map{ |r| r[0].to_i }.reject{ |r| r < 0 || r > 19 }
  ranks.empty? ? [0] : ranks
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
  ties ? " with ties" : ""
end

def format_tied(tied)
  tied ? " tied " : " "
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

def send_file(event, data, name, binary = false)
  tmpfile = File.join(Dir.tmpdir, name)
  File::open(tmpfile, "w", crlf_newline: !binary) do |f|
    f.write(data)
  end
  event.attach_file(File::open(tmpfile))
end

def send_top_n_count(event)
  msg = event.content
  player = parse_player(msg, event.user.name)
  rank = parse_rank(msg) || 1
  type = parse_type(msg)
  tabs = parse_tabs(msg)
  ties = !!(msg =~ /ties/i)
  tied = !!(msg =~ /\btied\b/i)

  if tied
    count = player.top_n_count(rank, type, tabs, true) - player.top_n_count(rank, type, tabs, false)
  else
    count = player.top_n_count(rank, type, tabs, ties)
  end

  header = format_rank(rank)
  type = format_type(type).downcase
  tabs = format_tabs(tabs)
  ties = format_ties(ties)
  tied = format_tied(tied)

  event << "#{player.name} has #{count}#{tied}#{tabs}#{type} #{header} scores#{ties}."
end

def send_rankings(event)
  msg = event.content
  type = parse_type(msg)
  tabs = parse_tabs(msg)
  rank = parse_rank(msg) || 1
  ties = !!(msg =~ /ties/i)

  if msg =~ /average/i
    if msg =~ /point/i
      players = Player.where(id: Player.joins(:scores).group('players.id').having("count(highscoreable_id) > #{MIN_SCORES}").pluck(:id))
      rankings = players.rankings { |p| p.average_points(type, tabs) }
      header = "average point rankings "
    elsif msg =~ /lead/i
      rankings = Player.rankings { |p| p.average_lead(type, tabs) }
      header = "average lead rankings "
    else
      players = Player.where(id: Player.joins(:scores).group('players.id').having("count(highscoreable_id) > #{MIN_SCORES}").pluck(:id))
      rankings = players.rankings { |p| p.average_points(type, tabs) }.map{ |p| [p[0], 20 - p[1]] }
      header = "average rank rankings "
    end
  elsif msg =~ /point/i
    rankings = Player.rankings { |p| p.points(type, tabs) }
    header = "point rankings "
  elsif msg =~ /score/i
    rankings = Player.rankings { |p| p.total_score(type, tabs) }
    header = "score rankings "
  elsif msg =~ /tied/i
    rankings = Player.rankings { |p| p.top_n_count(1, type, tabs, true) - p.top_n_count(1, type, tabs, false) }
    header = "tied 0th rankings "
  else
    rankings = Player.rankings { |p| p.top_n_count(rank, type, tabs, ties) }
    rank = format_rank(rank)
    ties = (ties ? "with ties " : "")
    header = "#{rank} rankings #{ties}"
  end

  type = format_type(type)
  tabs = format_tabs(tabs)

  top = rankings.take(NUM_ENTRIES).select { |r| r[1] > 0 }
  score_padding = top.map{ |r| r[1].to_i.to_s.length }.max
  name_padding = top.map{ |r| r[0].name.length }.max
  format = top[0][1].is_a?(Integer) ? "%#{score_padding}d" : "%#{score_padding + 4}.3f"

  top = top.each_with_index
           .map { |r, i| "#{HighScore.format_rank(i)}: #{r[0].format_name(name_padding)} - #{format % r[1]}" }
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
  player = msg[/for (.*)[\.\?]?/i, 1]
  smallest = !!(msg =~ /smallest/)

  if n == 0
    event << "I can't show you the spread between 0th and 0th..."
    return
  end

  spreads = HighScore.spreads(n, type, tabs, player)
  padding = spreads.map{ |s| s[1] }.max.to_i.to_s.length + 4

  spreads = spreads.sort_by { |s| (smallest ? s[1] : -s[1]) }
            .take(NUM_ENTRIES)
            .each_with_index
            .map { |s, i| "#{"%02d" % i}: #{"%-10s" % s[0]} - #{"%#{padding}.3f" % s[1]} - #{s[2]}"}
            .join("\n")

  spread = smallest ? "smallest" : "largest"
  rank = (n == 1 ? "1st" : (n == 2 ? "2nd" : (n == 3 ? "3rd" : "#{n}th")))
  type = format_type(type).downcase
  tabs = tabs.empty? ? "All " : format_tabs(tabs)

  event << "#{tabs}#{type}s #{!player.nil? ? "owned by #{player} " : ""}with the #{spread} spread between 0th and #{rank}:\n```#{spreads}```"
end

def send_scores(event)
  msg = event.content
  scores = parse_level_or_episode(msg)
  if scores.update_scores == -1
    event.send_message("Connection to the server failed, sending local cached scores.\n")
  end

  # Send immediately here - using << delays sending until after the event has been processed,
  # and we want to download the scores for the episode in the background after sending since it
  # takes a few seconds
  event.send_message("Current high scores for #{scores.format_name}:\n```#{scores.format_scores(scores.max_name_length) rescue ""}```")

  if scores.is_a?(Episode)
    event.send_message("The cleanliness of this episode 0th is %.3f." % [scores.cleanliness[1].to_s])
    Level.where("UPPER(name) LIKE ?", scores.name.upcase + '%').each(&:update_scores)
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

  totals = counts[:levels].zip(counts[:episodes]).zip(counts[:stories]).map(&:flatten)
           .each_with_index
           .map { |a, i| "#{HighScore.format_rank(i)}: #{"   %4d  %4d    %4d   %4d" % [a[0] + a[1], a[0], a[1], a[2]]}" }
           .join("\n\t")

  overall = "Totals:    %4d  %4d    %4d   %4d" % counts[:levels].zip(counts[:episodes]).zip(counts[:stories]).map(&:flatten)
            .map { |a| [a[0] + a[1], a[0], a[1], a[2]] }
            .reduce([0, 0, 0, 0]) { |sums, curr| sums.zip(curr).map { |a| a[0] + a[1] } }

  tabs = tabs.empty? ? "" : " in the #{format_tabs(tabs)} #{tabs.length == 1 ? 'tab' : 'tabs'}"

  event << "Player high score counts for #{player.name}#{tabs}:\n```        Overall Level Episode Column\n\t#{totals}\n#{overall}"
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
  player = msg[/for (.*)[\.\?]?/i, 1]
  type = parse_type(msg) || Level
  tabs = parse_tabs(msg)

  ties = HighScore.ties(type, tabs)
            .select { |s| s[1] < s[2] && !s[0].scores[0..s[1] - 1].map{ |s| s.player.name }.include?(player) }
            .sort_by { |s| -s[1] }
            .take(NUM_ENTRIES)
            .map { |s| "#{"%-10s" % s[0].name} - #{"%2d" % s[1]}" }
            .join("\n")

  type = format_type(type).downcase
  tabs = tabs.empty? ? "All " : format_tabs(tabs)
  player = player.nil? ? "" : " without " + player

  event << "#{tabs}#{type}s with the most ties for 0th #{format_time}#{player}:\n```\n#{ties}```"
end

def send_maxed(event)
  msg = event.content
  type = parse_type(msg) || Level
  tabs = parse_tabs(msg)

  ties = HighScore.ties(type, tabs)
            .select { |s| s[1] == s[2] }
            .map { |s| "#{s[0].name}\n" }
  ties_list = ties.join

  type = format_type(type).downcase
  tabs = tabs.empty? ? "All " : format_tabs(tabs)

  event << "#{tabs}potentially maxed #{type}s (with at least 20 ties for 0th) #{format_time}:\n" +
  "```\n#{ties_list}```There's a total of #{ties.count{|s| s.length>1}} potentially maxed #{type}s."
end

def send_cleanliness(event)
  msg = event.content
  tabs = parse_tabs(msg)
  cleanest = !!msg[/cleanest/i]
  episodes = tabs.empty? ? Episode.all : Episode.where(tab: tabs)

  cleanliness = episodes.map{ |e| e.cleanliness }
  padding = cleanliness.map{ |e| e[1] }.max.to_i.to_s.length + 4

  cleanliness = cleanliness.sort_by{ |e| (cleanest ? e[1] : -e[1]) }
                .map{ |e| "#{e[0]}:#{e[0][1] == '-' ? "  " : " "}%#{padding}.3f" % [e[1]] }
                .take(NUM_ENTRIES)
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
  list = "```#{ownages_list}```" unless ownages.count == 0
  event << "#{tabs}episode ownages #{format_time}:\n#{list}There're a total of #{ownages.count} episode ownages."
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
  n = (msg[/\b[0-9][0-9]?\b/] || NUM_ENTRIES / 2).to_i
  n = (n <= 0 || n > MAX_ENTRIES) ? NUM_ENTRIES / 2 : n

  improvable = player.improvable_scores(type, tabs)
  padding = improvable.map{ |level, gap| gap }.max.to_i.to_s.length + 4

  improvable = improvable.sort_by { |level, gap| -gap }
              .take(n)
              .map { |level, gap| "#{'%-10s' % [level]} (-#{"%#{padding}.3f" % [gap]})" }
              .join("\n")

  missing = player.missing_top_ns(20, type, tabs, false).sample(n).join("\n")
  type = type.to_s.downcase
  tabs = tabs.empty? ? "" :  " in the #{format_tabs(tabs)} #{tabs.length == 1 ? 'tab' : 'tabs'}"

  event << "#{n} most improvable #{type}s#{tabs} for #{player.name}:\n```#{improvable}```"
  event << "#{player.name} is not on the board for:\n```#{missing}```"
end

def send_level_id(event)
  level = parse_level_or_episode(event.content)
  raise "Episodes and stories don't have a name!" if level.is_a?(Episode) || level.is_a?(Story)
  event << "#{level.longname} is level #{level.name}."
end

def send_level_name(event)
  level = parse_level_or_episode(event.content.gsub(/level/, ""))
  raise "Episodes and stories don't have a name!" if level.is_a?(Episode) || level.is_a?(Story)
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

def send_average_rank(event)
  msg = event.content
  player = parse_player(msg, event.user.name)
  type = parse_type(msg)
  tabs = parse_tabs(msg)
  average = player.average_points(type, tabs)

  type = format_type(type).downcase
  tabs = format_tabs(tabs)
  event << "#{player.name} has an average #{type} #{tabs}rank of #{"%.3f" % [20 - average]}."
end

def send_average_lead(event)
  msg = event.content
  player = parse_player(msg, event.user.name)
  type = parse_type(msg)
  tabs = parse_tabs(msg)
  average = player.average_lead(type, tabs)

  type = format_type(type).downcase
  tabs = format_tabs(tabs)
  event << "#{player.name} has an average #{type} #{tabs}lead of #{"%.3f" % [average]}."
end

def send_splits(event)
  ep = parse_level_or_episode(event.content)
  ep = Episode.find_by(name: ep.name[0..-4]) if ep.class == Level
  raise "Columns can't be analyzed yet" if ep.class == Level
  r = (parse_rank(event.content) || 1) - 1
  splits = ep.splits(r)
  if splits.nil?
    event << "Sorry, that rank doesn't seem to exist for at least some of the levels."
    return
  end

  rank = (r == 1 ? "1st" : (r == 2 ? "2nd" : (r == 3 ? "3rd" : "#{r}th")))
  event << "#{rank} splits for episode #{ep.name}: `#{splits.map{ |s| "%.3f, " % s }.join[0..-3]}`."
  event << "#{rank} time: `#{"%.3f" % ep.scores[r].score}`. #{rank} cleanliness: `#{"%.3f" % ep.cleanliness(r)[1].to_s}`."
end

def send_diff(event)
  type = parse_type(event.content) || Level
  current = get_current(type)
  old_scores = get_saved_scores(type)
  since = (type == Level ? "yesterday" : (type == Episode ? "last week" : "last month"))

  diff = current.format_difference(old_scores)
  event << "Score changes on #{current.format_name} since #{since}:\n```#{diff}```"
end

def do_analysis(scores, rank)
  run = scores.get_replay_info(rank)
  return nil if run.nil?

  player = run['user_name']
  replay_id = run['replay_id'].to_s
  score = "%.3f" % [run['score'].to_f / 1000]
  analysis = scores.analyze_replay(replay_id)
  gold = "%.0f" % [((run['score'].to_f / 1000) + (analysis.size.to_f / 60) - 90) / 2]
  {'player' => player, 'scores' => scores.format_name, 'rank' => rank, 'score' => score, 'analysis' => analysis, 'gold' => gold}
end

def send_analysis(event)
  msg = event.content
  scores = parse_level_or_episode(msg)
  raise "Episodes and columns can't be analyzed (yet)" if scores.is_a?(Episode) || scores.is_a?(Story)
  ranks = parse_ranks(msg)
  analysis = ranks.map{ |rank| do_analysis(scores, rank) }.compact
  length = analysis.map{ |a| a['analysis'].size }.max
  raise "Connection failed" if !length || length == 0
  padding = Math.log(length, 10).to_i + 1
  table_header = " " * padding + "|" + "JRL|" * analysis.size
  separation = "-" * table_header.size

  # 3 types of result formatting, only 2 being used.

  raw_result = analysis.map{ |a|
    a['analysis'].map{ |b|
      [b % 2 == 1, b / 2 % 2 == 1, b / 4 % 2 == 1]
    }.map{ |f|
      frame = ""
      if f[0] then frame.concat("j") end
      if f[1] then frame.concat("r") end
      if f[2] then frame.concat("l") end
      frame
    }.join(".")
  }.join("\n\n")

  table_result = analysis.map{ |a|
    table = a['analysis'].map{ |b|
      [b % 2 == 1 ? "^" : " ", b / 2 % 2 == 1 ? ">" : " ", b / 4 % 2 == 1 ? "<" : " "].push("|")
    }
    while table.size < length do table.push([" ", " ", " ", "|"]) end
    table.transpose
  }.flatten(1)
   .transpose
   .each_with_index
   .map{ |l, i| "%0#{padding}d|#{l.join}" % [i + 1] }
   .insert(0, table_header)
   .insert(1, separation)
   .join("\n")

  key_result = analysis.map{ |a|
    a['analysis'].map{ |f|
      case f
      when 0 then "-"
      when 1 then "^"
      when 2 then ">"
      when 3 then "/"
      when 4 then "<"
      when 5 then "\\"
      when 6 then "≤"
      when 7 then "|"
      else "?"
      end
    }.join
     .scan(/.{,60}/)
     .reject{ |f| f.empty? }
     .each_with_index
     .map{ |f, i| "%0#{padding}d #{f}" % [60*i] }
     .join("\n")
  }.join("\n\n")

  properties = analysis.map{ |a|
    "[#{a['player']}, #{a['score']}, #{a['analysis'].size}f, rank #{a['rank']}, gold #{a['gold']}]"
  }.join("\n")
  explanation = "[**-** Nothing, **^** Jump, **>** Right, **<** Left, **/** Right Jump, **\\\\** Left Jump, **≤** Left Right, **|** Left Right Jump]"
  header = "Replay analysis for #{scores.format_name} #{format_time}.\n#{properties}\n#{explanation}"

  result = "#{header}\n```#{key_result}```"
  if result.size > 2000 then result = result[0..1993] + "...```" end
  event << "#{result}"
  tmpfile = File.join(Dir.tmpdir, "analysis-#{scores.name}.txt")
  File::open(tmpfile, "w", crlf_newline: true) do |f|
    f.write(table_result)
  end
  event.attach_file(File::open(tmpfile))
end

def send_history(event)
  # Stylistic parameters
  subdivisions = 20 # y axis subdivisions, roughly
  min = 10          # minimum y axis max
  players = 10      # amount of players to be plotted

  msg = event.content

  type = parse_type(msg)
  tabs = parse_tabs(msg)
  rank = parse_rank(msg) || 1
  ties = !!(msg =~ /ties/i)
  max = msg[/\b\d+\b/].to_i
  max = max > min ? max : Float::INFINITY

  if msg =~ /point/
    history = Player.points_histories(type, tabs)
    header = "point"
  elsif msg =~ /score/
    history = Player.score_histories(type, tabs)
    header = "score"
  else
    history = Player.rank_histories(rank, type, tabs, ties)
    header = format_rank(rank) + format_ties(ties)
  end

  history = history.sort_by { |player, data| data.max_by { |k, v| v }[1] }
            .reverse
            .select { |player, data| data.any? { |k, v| v <= max } } # remove players out of scope
            .take(players)
            .map { |player, data| [player, data.select{ |k, v| v <= max }] }.to_h # remove entries out of scope
            .select { |player, data| data.any? { |k, v| v > rank * 2 * tabs.length } }

  # Find all dates being plotted, keep just the first one for each month, and format for x axis labels.
  dates = history.map{ |player, data| data.keys }.flatten(1)
                 .uniq.map{ |date| date.to_s[0..6] }.reverse
  (0 .. dates.size - 2).each { |i| if dates[i] == dates[i + 1] then dates[i] = nil end }
  dates = dates.reverse.each_with_index.map{ |date, i| [i, !date.nil? ? date[5..6] : nil] }
               .to_h.select{ |i, date| !date.nil? }
  log(dates)

  # Calculate appropriate y axis increment and y axis max
  max = [history.map { |player, data| data.max_by { |k, v| v }[1] }.max, max].min
  nearest = 10 ** Math.log(max, 10).to_i / subdivisions
  nearest = nearest > 0 ? nearest : 5
  increment = (((max.to_f / subdivisions).to_i + 4) / nearest)
  increment = increment > 0 ? nearest * increment : 1

  type = format_type(type)
  tabs = format_tabs(tabs)

  graph = Gruff::Line.new(1280, 2000)
  graph.title = "#{type} #{tabs}#{header} history"
  graph.theme_pastel
  graph.colors = []
  graph.legend_font_size = 10
  graph.marker_font_size = 10
  graph.legend_box_size = 10
  graph.line_width = 1
  graph.hide_dots = true
  graph.y_axis_increment = increment
  #graph.labels = {0 => '2017'} # we need to index by Time instead of Integer, fix!
  graph.reference_line_default_width = 1
  graph.reference_line_default_color = 'grey'
  dates.each{ |i, date| if !date.nil? then graph.reference_lines[date] = { :index => i } end }
  #graph.x_axis_label = "Date"

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

  history.each { |player, data|
    graph.dataxy(player, data.keys, data.values)
  }

  graph.minimum_value = 0
  graph.maximum_value = max

  tmpfile = File.join(Dir.tmpdir, "history.png")
  graph.write(tmpfile)

  event.attach_file(File.open(tmpfile))
end

def identify(event)
  msg = event.content
  user = event.user.name
  nick = msg[/my name is (.*)[\.]?$/i, 1]

  raise "I couldn't figure out who you were! You have to send a message in the form 'my name is <username>.'" if nick.nil?

  user = User.find_or_create_by(username: user)
  user.player = nick
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
  $bot.update_status("online", "inne's evil cousin", nil, 0, false, 0)
  event << "Hi!"

  if $channel.nil?
    $channel = event.channel
    $mapping_channel = event.channel
    puts "Main channel established: #{$channel.name}." if !$channel.nil?
    puts "Mapping channel established: #{$mapping_channel.name}." if !$mapping_channel.nil?
    send_times(event)
  end
end

def thanks(event)
  event << "You're welcome!"
end

def faceswap(event)
  filename = Dir.entries("images/avatars").select{ |f| File.file?("images/avatars/" + f) }.sample
  file = File.open("images/avatars/" + filename)
  $bot.profile.avatar = file
  file.close
  event << "Remember changing the avatar has a 10 minute cooldown!"
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

def send_story_time(event)
  next_story = get_next_update(Story) - Time.now

  next_story_days = (next_story / (24 * 60 * 60)).to_i
  next_story_hours = (next_story / (60 * 60)).to_i - (next_story / (24 * 60 * 60)).to_i * 24

  event << "I'll post a new column of the month in #{next_story_days} days and #{next_story_hours} hours."
end

def send_times(event)
  send_level_time(event)
  send_episode_time(event)
  send_story_time(event)
end

def send_help(event)
  if (event.channel.type != 1) then
    event << "Hi! I'm **outte++**, the N++ Highscoring Bot and inne++'s evil cousin. I can do many tasks, like:\n"
    event << "- Fetching **scores** and **screenshots** for any level or episode."
    event << "- Performing highscore **rankings** of many sorts."
    event << "- Elaborating varied highscoring **stats**."
    event << "- Displaying a diverse assortment of interesting highscore **lists**."
    event << "- Searching and downloading **userlevels**."
    event << "- ... and many more things.\n"
    event << "For more details and a list of commands, please DM me this question, so as to avoid spamming this channel."
    return
  end

  msg = "Hi! I'm **outte++**, the N++ Highscoring Bot and inne++'s evil cousin. The commands I understand are:\n"

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

def send_story(event)
  event << "The current column of the month is #{get_current(Story).format_name}."
end

def dump(event)
  log("current level/episode/story: #{get_current(Level).format_name}, #{get_current(Episode).format_name}, #{get_current(Story).format_name}") unless get_current(Level).nil?
  log("next updates: scores #{get_next_update('score')}, level #{get_next_update(Level)}, episode #{get_next_update(Episode)}, story #{get_next_update(Story)}")

  event << "I dumped some things to the log for you to look at."
end

def send_videos(event)
  videos = parse_videos(event.content)

  # If we have more than one video, we probably shouldn't spam the channel too hard...
  # so we'll make people be more specific unless we can narrow it down.
  if videos.length == 1
    event << videos[0].url
    return
  end

  descriptions = videos.map(&:format_description).join("\n")
  default = videos.where(challenge: ["G++", "?!"])

  # If we don't have a specific challenge to look up, we default to sending
  # one without challenges
  if default.length == 1
    # Send immediately, so the video link shows above the additional videos
    event.send_message(default[0].url)
    event << "\nI have some challenge videos for this level as well! You can ask for them by being more specific about challenges and authors, by saying '<challenge> video for <level>' or 'video for <level> by <author>':\n```#{descriptions}```"
    return
  end

  event << "You're going to have to be more specific! I know about the following videos for this level:\n```#{descriptions}```"
end

# TODO set level of the day on startup
def respond(event)
  msg = event.content

  # strip off the @inne++ mention, if present
  msg.sub!(/\A<@!?[0-9]*> */, '') # IDs might have an exclamation mark

  # match exactly "lotd" or "eotw", regardless of capitalization or leading/trailing whitespace
  if msg =~ /\A\s*lotd\s*\Z/i
    send_level(event)
    return
  elsif msg =~ /\A\s*eotw\s*\Z/i
    send_episode(event)
    return
  elsif msg =~ /\A\s*cotm\s*\Z/i
    send_story(event)
    return
  end

  # userlevel methods
  if !!msg[/userlevel/i]
    respond_userlevels(event)
    return
  end

  # exclusively global methods, this conditional avoids the problem stated in the comment below
  if !msg[NAME_PATTERN, 2]
    send_rankings(event)    if msg =~ /rank/i && msg !~ /history/i
    send_history(event)     if msg =~ /history/i && msg !~ /rank/i
    send_diff(event)        if msg =~ /diff/i
    send_community(event)   if msg =~ /community/i
    send_cleanliness(event) if msg =~ /cleanest/i || msg =~ /dirtiest/i
    send_ownages(event)     if msg =~ /ownage/i
    send_help(event)        if msg =~ /\bhelp\b/i || msg =~ /\bcommands\b/i
  end

  # on this methods, we will exclude a few problematic words that appear
  # in some level names which would accidentally trigger them
  hello(event)               if msg =~ /\bhello\b/i || msg =~ /\bhi\b/i
  thanks(event)              if msg =~ /\bthank you\b/i || msg =~ /\bthanks\b/i
  dump(event)                if msg =~ /dump/i
  send_level(event)          if msg =~ /what.*(level|lotd)/i
  send_episode(event)        if msg =~ /what.*(episode|eotw)/i
  send_story(event)          if msg =~ /what.*(story|column|cotm)/i
  send_level_time(event)     if msg =~ /(when|next).*(level|lotd)/i
  send_episode_time(event)   if msg =~ /(when|next).*(episode|eotw)/i
  send_story_time(event)     if msg =~ /(when|next).*(story|column|cotm)/i
  send_points(event)         if msg =~ /\bpoints/i && msg !~ /history/i && msg !~ /rank/i && msg !~ /average/i && msg !~ /floating/i && msg !~ /legrange/i
  send_spreads(event)        if msg =~ /spread/i
  send_average_points(event) if msg =~ /\bpoints/i && msg !~ /history/i && msg !~ /rank/i && msg =~ /average/i && msg !~ /floating/i && msg !~ /legrange/i
  send_average_rank(event)   if msg =~ /average/i && msg =~ /rank/i && msg !~ /history/i && !!msg[NAME_PATTERN, 2]
  send_average_lead(event)   if msg =~ /average/i && msg =~ /lead/i && !!msg[NAME_PATTERN, 2]
  send_scores(event)         if msg =~ /scores/i && !!msg[NAME_PATTERN, 2]
  send_total_score(event)    if msg =~ /total\b/i && msg !~ /history/i && msg !~ /rank/i
  send_top_n_count(event)    if msg =~ /how many/i
  send_stats(event)          if msg =~ /\bstat/i && msg !~ /generator/i && msg !~ /hooligan/i && msg !~ /space station/i
  send_screenshot(event)     if msg =~ /screenshot/i
  send_suggestions(event)    if msg =~ /worst/i && msg !~ /nightmare/i
  send_list(event)           if msg =~ /\blist\b/i && msg !~ /of inappropriate words/i
  send_missing(event)        if msg =~ /missing/i
  send_maxable(event)        if msg =~ /maxable/i
  send_maxed(event)          if msg =~ /maxed/i
  send_level_name(event)     if msg =~ /\blevel name\b/i
  send_level_id(event)       if msg =~ /\blevel id\b/i
  send_analysis(event)       if msg =~ /analysis/i
  send_splits(event)         if msg =~ /\bsplits\b/i
  identify(event)            if msg =~ /my name is/i
  add_steam_id(event)        if msg =~ /my steam id is/i
  send_videos(event)         if msg =~ /\bvideo\b/i || msg =~ /\bmovie\b/i
  faceswap(event)            if msg =~ /faceswap/i

rescue RuntimeError => e
  # Exceptions raised in here are user error, indicating that we couldn't
  # figure out what they were asking for, so send the error message out
  # to the channel
  event << e
end
