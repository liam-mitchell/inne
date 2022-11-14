require 'ascii_charts'
require 'damerau-levenshtein'
require 'gruff'
require 'zlib'
require 'zip'
require_relative 'constants.rb'
require_relative 'utils.rb'
require_relative 'io.rb'
require_relative 'models.rb'
require_relative 'userlevels.rb'

# Return total count of player's scores within a specific rank range
def send_top_n_count(event)
  msg    = event.content
  player = parse_player(msg, event.user.name)
  type   = parse_type(msg)
  tabs   = parse_tabs(msg)
  range  = parse_range(msg)
  ties   = !!(msg =~ /ties/i)
  tied   = !!(msg =~ /\btied\b/i)
  sing   = !!(msg =~ /\bsingular\b/i)
  plur   = !!(msg =~ /\bplural\b/i)

  # The range must make sense
  if !range[2]
    event << "You specified an empty range! (#{format_range(range[0], range[1])})"
    return
  end

  # Retrieve score count in specified range
  if sing
    count = player.singular(type, tabs, false).values.map(&:size).sum
  elsif plur
    count = player.singular(type, tabs, true).values.map(&:size).sum
  elsif tied
    count = player.range_n_count(range[0], range[1], type, tabs, true) - player.range_n_count(range[0], range[1], type, tabs, false)
  else
    count = player.range_n_count(range[0], range[1], type, tabs, ties)
  end

  max   = find_max(:rank, type, tabs)
  type  = format_type(type).downcase
  tabs  = format_tabs(tabs)
  range = sing ? 'singular' : (plur ? 'plural' : format_range(range[0], range[1]))
  ties  = format_ties(ties)
  tied  = format_tied(tied)

  event << "#{player.print_name} has #{count} out of #{max} #{tied}#{tabs}#{type} #{range} scores#{ties}."
end

def send_rankings(event, page: nil, type: nil, tab: nil, rtype: nil, ties: nil)
  # PARSE ranking parameters
  initial    = page.nil? && type.nil? && tab.nil? && rtype.nil? && ties.nil?
  reset_page = !type.nil? || !tab.nil? || !rtype.nil? || !ties.nil?
  msg  = fetch_message(event, initial)
  type = parse_type(msg, type, true, initial)
  tabs = parse_tabs(msg, tab)
  rtype = rtype || parse_rtype(msg)
  rank = parse_rank(rtype) || parse_rank(msg) || 1
  ties = !ties.nil? ? ties : parse_ties(msg, rtype)
  play = parse_many_players(msg)
  nav  = !!msg[/\bnav((igat)((e)|(ing)))?\b/i] || !initial
  full = parse_global(msg) || parse_full(msg) || nav
  tab  = tabs.empty? ? 'all' : (tabs.size == 1 ? tabs[0].to_s.downcase : 'tab')
  rtype = fix_rtype(rtype, rank)

  # EXECUTE specific rankings
  case rtype
  when 'average_point'
    rankings = Score.rank(:avg_points, type, tabs, ties, nil, full, play)
    max      = find_max(:avg_points, type, tabs, !initial)
  when 'average_top1_lead'
    rankings = Score.rank(:avg_lead, type, tabs, nil, nil, full, play)
    max      = nil
  when 'average_rank'
    rankings = Score.rank(:avg_rank, type, tabs, ties, nil, full, play)
    max      = find_max(:avg_rank, type, tabs, !initial)
  when 'point'
    rankings = Score.rank(:points, type, tabs, ties, nil, full, play)
    max      = find_max(:points, type, tabs, !initial)
  when 'score'
    rankings = Score.rank(:score, type, tabs, nil, nil, full, play)
    max      = find_max(:score, type, tabs, !initial)
  when 'singular_top1'
    rankings = Score.rank(:singular, type, tabs, nil, 1, full, play)
    max      = find_max(:rank, type, tabs, !initial)
  when 'plural_top1'
    rankings = Score.rank(:singular, type, tabs, nil, 0, full, play)
    max      = find_max(:rank, type, tabs, !initial)
  when 'tied_top1'
    rankings = Score.rank(:tied_rank, type, tabs, true, rank - 1, full, play)
    max      = find_max(:rank, type, tabs, !initial)
  when 'maxed_top1'
    rankings = Score.rank(:maxed, type, tabs, nil, nil, full, play)
    max      = find_max(:maxed, type, tabs, !initial)
  when 'maxable_top1'
    rankings = Score.rank(:maxable, type, tabs, nil, nil, full, play)
    max      = find_max(:maxable, type, tabs, !initial)
  else
    rankings = Score.rank(:rank, type, tabs, ties, rank - 1, full, play)
    max      = find_max(:rank, type, tabs, !initial)
  end

  # PAGINATION
  pagesize = nav ? PAGE_SIZE : 20
  page = parse_page(msg, page, reset_page, event.message.components)
  pag  = compute_pages(rankings.size, page, pagesize)

  # FORMAT message
  min = "Minimum number of scores required: #{min_scores(type, tabs, !initial)}" if ['average_rank', 'average_point'].include?(rtype)
  #   Header
  tabs = format_tabs(tabs)
  header = "Rankings - #{format_full(full).capitalize}"
  header += full ? format_type(type, true).downcase : format_type(type, true)
  header += " #{tabs}#{format_rtype(rtype, nil, ties)}#{format_max(max)}"
  header += " without " + format_sentence(play.map(&:name)) if !play.empty?
  header += " #{format_time}:"
  #   Rankings
  score_padding = rankings.map{ |r| r[1].to_i.to_s.length }.max
  name_padding = rankings.map{ |r| r[0].print_name.length }.max
  format = rankings[0][1].is_a?(Integer) ? "%#{score_padding}d" : "%#{score_padding + 4}.3f" if !rankings.empty?
  if rankings.empty?
    rankings = "```These boards are empty!```"
  else
    rankings = rankings.each_with_index.to_a
    rankings = rankings[pag[:offset]...pag[:offset] + pagesize] if !full || nav
    rankings = rankings.map{ |r, i|
      "#{HighScore.format_rank(i)}: #{r[0].format_name(name_padding)} - #{format % r[1]}"
    }.join("\n")
    rankings = format_block(rankings)
  end
  #   Footer
  rankings.concat(min) if !min.nil? && (!full || nav)

  # SEND message
  if nav
    view = Discordrb::Webhooks::View.new
    interaction_add_button_navigation(view, pag[:page], pag[:pages])
    interaction_add_type_buttons(view, type, ties)
    interaction_add_select_menu_rtype(view, rtype)
    interaction_add_select_menu_metanet_tab(view, tab)
    send_message_with_interactions(event, header + "\n" + rankings, view, !initial)
  else
    length = header.length + rankings.length
    event << header
    length < DISCORD_LIMIT && !full ? event << rankings : send_file(event, rankings[4..-4], "rankings.txt")
  end
end

def send_total_score(event)
  player = parse_player(event.content, event.user.name)
  type = parse_type(event.content)
  tabs = parse_tabs(event.content)

  score = player.total_score(type, tabs)

  max  = find_max(:score, type, tabs)
  type = format_type(type).downcase
  tabs = format_tabs(tabs)

  event << "#{player.print_name}'s total #{tabs}#{type.to_s.downcase} score is #{"%.3f" % [score]} out of #{"%.3f" % max}."
end

def send_spreads(event)
  msg = event.content
  n = (parse_rank(msg) || 2) - 1
  type = parse_type(msg) || Level
  tabs = parse_tabs(msg)
  player = parse_player(msg, nil, false, true, false)
  smallest = !!(msg =~ /smallest/)
  raise "I can't show you the spread between 0th and 0th..." if n == 0

  spreads  = HighScore.spreads(n, type, tabs, smallest, player.nil? ? nil : player.id)
  namepad  = spreads.map{ |s| s[0].length }.max
  scorepad = spreads.map{ |s| s[1] }.max.to_i.to_s.length + 4
  spreads  = spreads.each_with_index
                    .map { |s, i| "#{"%02d" % i}: #{"%-#{namepad}s" % s[0]} - #{"%#{scorepad}.3f" % s[1]} - #{s[2]}"}
                    .join("\n")

  spread = smallest ? "smallest" : "largest"
  rank   = (n == 1 ? "1st" : (n == 2 ? "2nd" : (n == 3 ? "3rd" : "#{n}th")))
  type   = format_type(type).downcase
  tabs   = tabs.empty? ? "All " : format_tabs(tabs)
  event << "#{tabs}#{type}s #{!player.nil? ? "owned by #{player.print_name} " : ""}with the #{spread} spread between 0th and #{rank}:\n```#{spreads}```"
end

def send_scores(event, map = nil, ret = false, page: nil)
  initial = page.nil?
  msg     = fetch_message(event, initial)
  scores  = map.nil? ? parse_level_or_episode(msg, partial: true) : map
  offline = !!(msg[/offline/i])

  # Navigating scores goes into a different method (see below this one)
  if !!msg[/nav((igat)((e)|(ing)))?\s*(high\s*)?scores/i]
    send_nav_scores(event)
    return
  end

  # Multiple matches
  if scores.is_a?(Array)
    format_level_matches(event, msg, page, initial, scores, 'search')
    return
  end

  if OFFLINE_STRICT
    event << "Strict offline mode is ON, sending local cached scores.\n"
  elsif !offline && scores.update_scores == -1
    event << "Connection to the server failed, sending local cached scores.\n"
  end

  str = "Highscores for #{scores.format_name}:\n#{format_block(scores.format_scores(scores.max_name_length, Archive.zeroths(scores))) rescue ""}"
  if scores.is_a?(Episode)
    clean = scores.cleanliness[1]
    str += "The cleanliness of this episode 0th is %.3f (%df)." % [clean, (60 * clean).round]
  end
  event << str

  # Send immediately here - using << delays sending until after the event has been processed,
  # and we want to download the scores for the episode in the background after sending since it
  # takes a few seconds.
  res = ""
  res = event.drain_into(res)
  if ret
    return res
  else
    event.send_message(res)
  end

  if scores.is_a?(Episode)
    Level.where("UPPER(name) LIKE ?", scores.name.upcase + '%').each(&:update_scores) if !offline && !OFFLINE_STRICT
  end
end

# Navigating scores: Main differences:
# - Does not update the scores.
# - Adds navigating between levels.
# - Adds navigating between dates.
def send_nav_scores(event, offset: nil, date: nil, page: nil)
  initial = offset.nil? && date.nil? && page.nil?
  msg     = fetch_message(event, initial)
  scores  = parse_level_or_episode(msg, partial: true)

  # Multiple matches
  if scores.is_a?(Array)
    format_level_matches(event, msg, page, initial, scores, 'search')
    return
  end

  scores = scores.nav(offset.to_i)
  dates  = Archive.changes(scores).sort.reverse
  
  if initial || date.nil?
    new_index = 0
  else
    old_date  = event.message.components[1].to_a[2].custom_id.to_s.split(':').last.to_i
    new_index = (dates.find_index{ |d| d == old_date } + date.to_i).clamp(0, dates.size - 1)
  end
  date = dates[new_index] || 0

  str = "Navigating high scores for #{scores.format_name}:\n"
  str += format_block(Archive.format_scores(Archive.scores(scores, date), Archive.zeroths(scores, date))) rescue ""
  str += "*Warning: Navigating scores does not update them.*"

  view = Discordrb::Webhooks::View.new
  interaction_add_level_navigation(view, scores.name.center(11, ' '))
  interaction_add_date_navigation(view, new_index + 1, dates.size, date, date == 0 ? " " * 11 : Time.at(date).strftime("%Y-%b-%d"))
  send_message_with_interactions(event, str, view, !initial)
end

# Prepared for navigation, but it's not possible to edit attachments for now,
# so commented that functionality and 'offset' not being used.
def send_screenshot(event, map = nil, ret = false, page: nil, offset: nil)
  initial = page.nil?
  msg     = fetch_message(event, initial)
  scores  = map.nil? ? parse_level_or_episode(msg, partial: true) : map
  nav     = !!msg[/\bnav((igat)((e)|(ing)))?\b/i] || !initial

  # Multiple matches
  if scores.is_a?(Array)
    format_level_matches(event, msg, page, initial, scores, 'search')
    return
  end

  # Single match
  #scores = scores.nav(offset.to_i)
  name = scores.name.upcase.gsub(/\?/, 'SS').gsub(/!/, 'SS2')
  screenshot = "screenshots/#{name}.jpg"

  if !File.exist?(screenshot)
    str = "I don't have a screenshot for #{scores.format_name}... :("
    return [nil, str] if ret
    return event.send_message(str)
  end
  
  str  = "Screenshot for #{scores.format_name}"
  file = File::open(screenshot)
  return [file, str] if ret
  if nav
    # Attachments can't be modified so we're stuck for now
    send_message_with_interactions(event, str, nil, false, [file])
  else
    event << str
    event.attach_file(file)
  end
end

def send_screenscores(event)
  msg = event.content
  map = parse_level_or_episode(msg)
  ss  = send_screenshot(event, map, true)
  s   = send_scores(event, map, true)

  if ss[0].nil?
    event.send_message(ss[1])
  else
    event.send_file(ss[0], caption: ss[1])
  end

  sleep(0.05)

  event.send_message(s)

end

def send_scoreshot(event)
  msg = event.content
  map = parse_level_or_episode(msg)
  s   = send_scores(event, map, true)
  ss  = send_screenshot(event, map, true)

  event.send_message(s)

  sleep(0.05)

  if ss[0].nil?
    event.send_message(ss[1])
  else
    event.send_file(ss[0], caption: ss[1])
  end
end

def send_stats(event)
  msg    = event.content
  player = parse_player(msg, event.user.name)
  tabs   = parse_tabs(msg)
  ties   = !!(msg =~ /ties/i)
  counts = player.score_counts(tabs, ties)

  histogram = AsciiCharts::Cartesian.new(
    (0..19).map{ |r| [r, counts[:levels][r].to_i + counts[:episodes][r].to_i] },
    bar: true,
    hide_zero: true,
    max_y_vals: 15,
    title: 'Score histogram'
  ).draw

  full_counts = (0..19).map{ |r|
    l = counts[:levels][r].to_i
    e = counts[:episodes][r].to_i
    s = counts[:stories][r].to_i
    [l + e, l, e, s]
  }

  totals  = full_counts.each_with_index.map{ |c, r| "#{HighScore.format_rank(r)}: #{"   %4d  %4d    %4d   %4d" % c}" }.join("\n\t")
  overall = "Totals:    %4d  %4d    %4d   %4d" % full_counts.reduce([0, 0, 0, 0]) { |sums, curr| sums.zip(curr).map { |a| a[0] + a[1] } }
  maxes   = [Level, Episode, Story].map{ |t| find_max(:rank, t, tabs) }
  maxes   = "Max:       %4d  %4d    %4d   %4d" % maxes.unshift(maxes[0] + maxes[1])
  tabs    = tabs.empty? ? "" : " in the #{format_tabs(tabs)} #{tabs.length == 1 ? 'tab' : 'tabs'}"
  msg1    = "Player high score counts for #{player.print_name}#{tabs}:\n```        Overall Level Episode Column\n\t#{totals}\n#{overall}\n#{maxes}"
  msg2    = "#{histogram}```"

  if msg1.length + msg2.length <= DISCORD_LIMIT
    event << msg1
    event << msg2
  else
    event.send_message(msg1 + "```")
    event.send_message("```" + msg2)
  end
end

def send_list(event)
  msg    = event.content
  player = parse_player(msg, event.user.name)
  type   = parse_type(msg)
  tabs   = parse_tabs(msg)
  rank   = parse_rank(msg) || 20
  bott   = parse_bottom_rank(msg) || 0
  sing   = !!(msg =~ /\bsingular\b/i)
  plur   = !!(msg =~ /\bplural\b/i)
  if rank == 20 && bott == 0 && !!msg[/0th/i]
    rank = 1
    bott = 0
  end
  all    =  sing ? player.singular(type, tabs, false) :
           (plur ? player.singular(type, tabs, true) :
            player.scores_by_rank(type, tabs, bott, rank))

  list = all.map{ |s| format_list_score(s) }
  count = list.count
  list = list.join("\n")
  if count <= 20
    event << format_block(list)
  else
    send_file(event, list, "scores-#{player.print_name.delete(":")}.txt", false)
  end
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

  text << "Total level score: #{"%.3f" % levels[0]}\n"
  text << "Total episode score: #{"%.3f" % episodes[0]}\n"
  text << (condition ? "Total level score (w/o secrets): #{"%.3f" % levels_no_secrets[0]}\n" : "")
  text << "Difference between level and episode 0ths: #{"%.3f" % [difference]}\n\n"
  text << "Average level score: #{"%.3f" % [levels[0]/levels[1]]}\n"
  text << "Average episode score: #{"%.3f" % [episodes[0]/episodes[1]]}\n"
  text << "Average difference between level and episode 0ths: #{"%.3f" % [difference/episodes[1]]}\n"

  event << "Community's total #{format_tabs(tabs)}scores #{format_time}:\n```#{text}```"
end

def send_maxable(event)
  msg    = event.content
  player = parse_player(msg, nil, false, true, false)
  type   = parse_type(msg) || Level
  tabs   = parse_tabs(msg)

  ties   = HighScore.ties(type, tabs, player.nil? ? nil : player.id, false)
            .take(NUM_ENTRIES)
            .map { |s| "#{"%-10s" % s[0]} - #{"%2d" % s[1]} - #{format_string(s[3])}" }
            .join("\n")

  type   = format_type(type).downcase
  tabs   = tabs.empty? ? "All " : format_tabs(tabs)
  player = player.nil? ? "" : " without " + player.print_name
  event << "#{tabs}#{type.pluralize} with the most ties for 0th #{format_time}#{player}:\n#{format_block(ties)}"
end

def send_maxed(event)
  msg    = event.content
  player = parse_player(msg, nil, false, true, false)
  type   = parse_type(msg) || Level
  tabs   = parse_tabs(msg)

  ties   = HighScore.ties(type, tabs, player.nil? ? nil : player.id, true)
                    .map { |s| "#{"%10s" % s[0]} - #{format_string(s[3])}" }
  count  = ties.count{ |s| s.length > 1 }
  block  = ties.join("\n")

  type   = format_type(type).downcase
  tabs   = tabs.empty? ? "All " : format_tabs(tabs)
  player = player.nil? ? "" : " without " + player.print_name
  header = "#{tabs}potentially maxed #{type.pluralize} #{format_time}#{player}:"
  footer = "There's a total of #{count} potentially maxed #{type.pluralize}."
  event << header
  count <= 20 ? event << format_block(block) + footer : send_file(event, block, "maxed-#{type.pluralize}.txt", false)
end

def send_cleanliness(event)
  msg = event.content
  tabs = parse_tabs(msg)
  cleanest = !!msg[/cleanest/i]

  cleanliness = Episode.cleanliness(tabs)
                       .sort_by{ |e| (cleanest ? e[1] : -e[1]) }
                       .take(NUM_ENTRIES)
#                       .each{ |e| e[1] = round_score(e[1]) }
  padding     = cleanliness.map{ |e| ("%.3f" % e[1]).length }.max
  cleanliness = cleanliness.map{ |e| "#{"%7s" % e[0]} - #{"%#{padding}.3f" % e[1]} - #{e[2]}" }.join("\n")

  tabs = tabs.empty? ? "All " : format_tabs(tabs)
  event << "#{tabs}#{cleanest ? "cleanest" : "dirtiest"} episodes #{format_time}:\n```#{cleanliness}```"
end

def send_ownages(event)
  msg = event.content
  tabs = parse_tabs(msg)
  episodes = tabs.empty? ? Episode.all : Episode.where(tab: tabs)

  ownages = Episode.ownages(tabs)
  list    = ownages.map{ |e, p| "#{"%7s" % e} - #{p}" }.join("\n")
  count   = ownages.count
  if count == 0
    block = ""
  elsif count <= 20
    block = "```" + list + "```"
  else
    block = "```" + ownages.group_by{ |e, p| p }.map{ |p, o| "#{format_string(p)} - #{o.count}" }.join("\n") + "```"
  end

  tabs_s = tabs.empty? ? "All " : format_tabs(tabs)
  tabs_e = tabs.empty? ? "" : format_tabs(tabs)
  event << "#{tabs_s}episode ownages#{format_max(find_max(:rank, Episode, tabs))} #{format_time}:#{block}There're a total of #{count} #{tabs_e}episode ownages."
  send_file(event, list, "ownages.txt") if count > 20
end

def send_missing(event)
  msg = event.content
  player = parse_player(msg, event.user.name)
  type = parse_type(msg)
  tabs = parse_tabs(msg)
  rank = parse_rank(msg) || 20
  ties = !!(msg =~ /ties/i)

  missing = player.missing_top_ns(type, tabs, rank, ties)
  count = missing.count
  missing = missing.join("\n")
  if count <= 20
    event << format_block(missing)
  else
    send_file(event, missing, "missing-#{player.print_name.delete(":")}.txt", false)
  end
end

def send_suggestions(event)
  msg = event.content
  player = parse_player(msg, event.user.name)
  type = parse_type(msg)
  tabs = parse_tabs(msg)

  improvable = player.improvable_scores(type, tabs, NUM_ENTRIES)
  padding = improvable.map{ |level, gap| gap }.max.to_i.to_s.length + 4
  improvable = improvable.map { |level, gap| "#{'%-10s' % [level]} - #{"%#{padding}.3f" % [gap]}" }.join("\n")

  tabs = format_tabs(tabs)
  type = format_type(type).downcase
  event << "Most improvable #{tabs}#{type} scores for #{player.print_name}:\n#{format_block(improvable)}"
end

def send_level_id(event, page: nil)
  initial = page.nil?
  msg     = fetch_message(event, initial)
  level  = parse_level_or_episode(msg, partial: true)

  # Multiple matches
  if level.is_a?(Array)
    format_level_matches(event, msg, page, initial, level, 'search')
    return
  end

  # Single match
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

  max  = find_max(:points, type, tabs)
  type = format_type(type).downcase
  tabs = format_tabs(tabs)
  event << "#{player.print_name} has #{points} out of #{max} #{type} #{tabs}points."
end

def send_average_points(event)
  msg = event.content
  player = parse_player(msg, event.user.name)
  type = parse_type(msg)
  tabs = parse_tabs(msg)
  average = player.average_points(type, tabs)

  max  = find_max(:avg_points, type, tabs)
  type = format_type(type).downcase
  tabs = format_tabs(tabs)
  event << "#{player.print_name} has #{"%.3f" % [average]} out of #{"%.3f" % max} #{type} #{tabs}average points."
end

def send_average_rank(event)
  msg = event.content
  player = parse_player(msg, event.user.name)
  type = parse_type(msg)
  tabs = parse_tabs(msg)
  average = player.average_points(type, tabs)

  type = format_type(type).downcase
  tabs = format_tabs(tabs)
  event << "#{player.print_name} has an average #{type} #{tabs}rank of #{"%.3f" % [20 - average]}."
end

def send_average_lead(event)
  msg = event.content
  player = parse_player(msg, event.user.name)
  type = parse_type(msg) || Level
  tabs = parse_tabs(msg)
  average = player.average_lead(type, tabs)

  type = format_type(type).downcase
  tabs = format_tabs(tabs)
  event << "#{player.print_name} has an average #{type} #{tabs}lead of #{"%.3f" % [average]}."
end

def send_table(event)
  msg    = event.content
  player = parse_player(msg, event.user.name)
  range  = parse_range(msg)
  global = false
  ties   = !!(msg =~ /ties/i)
  avg    = !!(msg =~ /average/i)

  # The range must make sense
  if !range[2]
    event << "You specified an empty range! (#{format_range(range[0], range[1])})"
    return
  end

  if avg
    if msg =~ /point/i
      table   = player.table(:avg_points, ties, nil, nil)
      header  = "average points table"
    else
      table   = player.table(:avg_rank, ties, nil, nil)
      header  = "average rank table"
    end
  elsif msg =~ /point/i
    table   = player.table(:points, ties, nil, nil)
    header  = "points table"
  elsif msg =~ /score/i
    table   = player.table(:score, ties, nil, nil)
    header  = "total score table"
  elsif msg =~ /tied/i
    table   = player.table(:tied, ties, range[0], range[1])
    header  = "tied #{rank.ordinalize} table"
  elsif msg =~ /maxed/i
    table   = player.table(:maxed, ties, nil, nil)
    header  = "maxed scores table"
    global  = true
  elsif msg =~ /maxable/i
    table   = player.table(:maxable, ties, nil, nil)
    header  = "maxable scores table"
    global  = true
  else
    table   = player.table(:rank, ties, range[0], range[1])
    header  = "#{format_range(range[0], range[1])} table"
  end

  # construct table
  if avg
    scores = player.table(:rank, ties, 0, 20)
    totals = Level::tabs.map{ |tab, id|
      lvl = scores[0][tab] || 0
      ep  = scores[1][tab] || 0
      [format_tab(tab.to_sym), lvl, ep, lvl + ep]
    }
  end
  table = Level::tabs.each_with_index.map{ |tab, i|
    lvl = table[0][tab[0]] || 0
    ep  = table[1][tab[0]] || 0
    [format_tab(tab[0].to_sym), lvl, ep, avg ? wavg([lvl, ep], totals[i][1..2]) : lvl + ep]
  }

  # format table
  rows = []
  rows << ["", "Level", "Episode", "Total"]
  rows << :sep
  rows += table
  rows << :sep
  if !avg
    rows << [
      "Total",
      table.map(&:second).sum,
      table.map(&:third).sum,
      table.map(&:fourth).sum
    ]
  else
    rows << [
      "Total",
      wavg(table.map(&:second), totals.map(&:second)),
      wavg(table.map(&:third),  totals.map(&:third)),
      wavg(table.map(&:fourth), totals.map(&:fourth))
    ]
  end
  player = global ? "" : "#{player.format_name.strip}'s "
  event << "#{player}#{global ? header.capitalize : header} #{format_time}:```#{make_table(rows)}```"  
end

def send_comparison(event)
  msg    = event.content
  type   = parse_type(msg)
  tabs   = parse_tabs(msg)
  p1, p2 = parse_players(msg, event.user.name)
  comp   = Player.comparison(type, tabs, p1, p2)
  counts = comp.map{ |t| t.map{ |r, s| s.size }.sum }

  header = "#{format_type(type)} #{format_tabs(tabs)}comparison between #{p1.tname} and #{p2.tname} #{format_time}:"
  rows = ["Scores with only #{p1.tname}"]
  rows << "Scores where #{p1.tname} > #{p2.tname}"
  rows << "Scores where #{p1.tname} = #{p2.tname}"
  rows << "Scores where #{p1.tname} < #{p2.tname}"
  rows << "Scores with only #{p2.tname}"
  l = rows.map(&:length).max
  table = rows.zip(counts).map{ |r, c| r.ljust(l) + " - " + c.to_s.rjust(4) }.join("\n")
  list = (0..4).map{ |i|
           rows[i] + ":\n\n" + comp[i].map{ |r, s|
             s.map{ |e|
               e.size == 2 ? format_pair(e) : format_entry(e)
             }.join("\n")
           }.join("\n") + "\n"
         }.join("\n")

  event << header + "```" + table + "```"
  send_file(event, list, "comparison-#{p1.tname}-#{p2.tname}.txt")
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

  clean = ep.cleanliness(r)[1]
  rank = (r == 1 ? "1st" : (r == 2 ? "2nd" : (r == 3 ? "3rd" : "#{r}th")))
  event << "#{rank} splits for episode #{ep.name}: `#{splits.map{ |s| "%.3f, " % s }.join[0..-3]}`."
  event << "#{rank} time: `#{"%.3f" % ep.scores[r].score}`. #{rank} cleanliness: `#{"%.3f (%df)" % [clean, (60 * clean).round]}`."
end

def send_random(event)
  msg    = event.content
  type   = parse_type(msg) || Level
  tabs   = parse_tabs(msg)
  amount = [msg[/\d+/].to_i || 1, NUM_ENTRIES].min

  maps = tabs.empty? ? type.all : type.where(tab: tabs)
  if amount > 1
    event << "Random selection of #{amount} #{format_tabs(tabs)}#{format_type(type).downcase.pluralize}:"
    event << "```" + maps.sample(amount).each_with_index.map{ |m, i| "#{"%2d" % i} - #{"%10s" % m.name}" }.join("\n") + "```"
  else
    map = maps.sample
    send_screenshot(event, map)
  end
end

def send_challenges(event, page: nil)
  initial = page.nil?
  msg     = fetch_message(event, initial)
  lvl     = parse_level_or_episode(msg, partial: true)

  # Multiple matches
  if lvl.is_a?(Array)
    format_level_matches(event, msg, page, initial, lvl, 'search')
    return
  end

  # Single match
  raise "#{lvl.class.to_s.pluralize.capitalize} don't have challenges!" if lvl.class != Level
  raise "#{lvl.tab.to_s} levels don't have challenges!" if ["SI", "SL"].include?(lvl.tab.to_s)
  event << "Challenges for #{lvl.longname} (#{lvl.name}):\n#{format_block(lvl.format_challenges)}"
end

def send_query(event, page: nil)
  initial = page.nil?
  msg     = fetch_message(event, initial)
  lvl     = parse_level_or_episode(msg, partial: true, array: true)
  format_level_matches(event, msg, page, initial, lvl, 'search')
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
  run      = scores.scores[rank]
  return nil if run.nil?

  analysis = run.demo.decode_demo
  {
    'player'   => run.player.name,
    'scores'   => scores.format_name,
    'rank'     => "%02d" % rank,
    'score'    => "%.3f" % run.score,
    'analysis' => analysis,
    'gold'     => "%.0f" % [(run.score + analysis.size.to_f / 60 - 90) / 2]
  }
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

  properties = "```" + analysis.map{ |a|
    "[#{format_string(a['player'])}, #{a['score']}, #{a['analysis'].size}f, rank #{a['rank']}, gold #{a['gold']}]"
  }.join("\n") + "```"
  explanation = "[**-** Nothing, **^** Jump, **>** Right, **<** Left, **/** Right Jump, **\\\\** Left Jump, **≤** Left Right, **|** Left Right Jump]"
  header = "Replay analysis for #{scores.format_name} #{format_time}.\n#{properties}\n#{explanation}"

  result = "#{header}"
  result += "```#{key_result}```" unless analysis.sum{ |a| a['analysis'].size } > 1080
  if result.size > DISCORD_LIMIT then result = result[0..DISCORD_LIMIT - 7] + "...```" end
  event << "#{result}"
  send_file(event, table_result, "analysis-#{scores.name}.txt")
end

def send_history(event)
  event << "Function not available yet, restructuring being done."
end

def send_history2(event)
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
  User.find_by(username: event.user.name).update(steam_id: id) if !User.find_by(username: event.user.name).nil? && User.find_by(steam_id: id).nil?
  event << "Thanks! From now on I'll try to use your Steam ID to retrieve scores when I need to."
end

def add_display_name(event)
  msg  = event.content
  name = msg[/my display name is (.*)[\.]?$/i, 1]
  raise "You need to specify some display name." if name.nil?
  user = User.find_by(username: event.user.name)
  if user.nil?
    event << "I don't know you, you first need to identify using 'my name is <player name>'."
  else
    user.update(displayname: name)
    user.player.update(display_name: name)
    event << "Great, from now on #{user.playername} will show up as #{name}."
  end
end

def hello(event)
  $bot.update_status("online", "inne's evil cousin", nil, 0, false, 0)
  event << "Hi!"

  if $channel.nil?
    $channel         = event.channel
    $mapping_channel = event.channel
    $nv2_channel     = event.channel
    $content_channel = event.channel
    $last_potato = $nv2_channel.history(1)[0].timestamp.to_i
    puts "Main channel established: #{$channel.name}."            if !$channel.nil?
    puts "Mapping channel established: #{$mapping_channel.name}." if !$mapping_channel.nil?
    puts "Nv2 channel established: #{$nv2_channel.name}."         if !$nv2_channel.nil?
    puts "Content channel established: #{$content_channel.name}." if !$content_channel.nil?
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

def make_table(rows, header = nil, sep_x = "=", sep_y = "|", sep_i = "x")
  text_rows = rows.select{ |r| r.is_a?(Array) }
  count = text_rows.map(&:size).max
  rows.each{ |r| if r.is_a?(Array) then r << "" while r.size < count end }
  widths = (0..count - 1).map{ |c| text_rows.map{ |r| (r[c].is_a?(Float) ? "%.3f" % r[c] : r[c].to_s).length }.max }
  sep = widths.map{ |w| sep_i + sep_x * (w + 2) }.join + sep_i + "\n"
  table = sep.dup
  table << sep_y + " " * (((sep.size - 1) - header.size) / 2) + header + " " * ((sep.size - 1) - ((sep.size - 1) - header.size) / 2 - header.size - 2) + sep_y + "\n" + sep if !header.nil?
  rows.each{ |r|
    if r == :sep
      table << sep
    else
      r.each_with_index{ |s, i|
        table << sep_y + " " + (s.is_a?(Numeric) ? (s.is_a?(Integer) ? s : "%.3f" % s).to_s.rjust(widths[i], " ") : s.to_s.ljust(widths[i], " ")) + " "
      }
      table << sep_y + "\n"
    end
  }
  table << sep
  return table
end

def send_help2(event)
  cols = 3

  msg = "Hi! I'm **outte++**, the N++ Highscoring Bot and inne++'s evil cousin."
  msg += "I can do many tasks, like fetching **scores** and **screenshots** of any level, "
  msg += "performing **rankings** and **stats**, retrieving **lists**, "
  msg += "browsing and downloading **userlevels**, etc."
  event << msg

  commands = [
    "lotd",
    "eotw",
    "cotm",
    "userlevel",
    "rank",
    "community",
    "cleanest",
    "dirtiest",
    "ownage",
    "help",
    "random",
    "what",
    "when",
    "points",
    "spread",
    "average points",
    "average rank",
    "average lead",
    "scores",
    "total",
    "how many",
    "stats",
    "screenshot",
    "worst",
    "list",
    "missing",
    "maxable",
    "maxed",
    "level name",
    "level id",
    "analysis",
    "splits",
    "my name is",
    "my steam id is",
    "video",
    "unique holders",
    "z"
  ]

  commands.sort!
  commands.push("") until commands.size % cols == 0
  col_s = commands.size / cols
  row = commands[0..col_s - 1]
  (1..cols - 1).each{ |i| row.zip(commands[i * col_s .. (i + 1) * col_s - 1]) }
  rows = row.flatten.compact.each_slice(cols).to_a
  event << "```#{make_table(rows, "COMMAND LIST")}```"
  
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

def send_unique_holders(event)
  ranks = [0] * 20
  Player.all.each { |p|
    rank = p.scores.map(&:rank).min
    next if rank.nil?
    (rank..19).each{ |r| ranks[r] += 1 }
  }
  ranks = ranks.each_with_index.map{ |r, i| "#{"%-2d" % i} - #{"%-3d" % r}" }.join("\n")
  event << "Number of unique highscore holders by rank at #{Time.now.to_s}\n```#{ranks}```"
end

# TODO: Implement a way to query next pages if there are more than 20 streams.
#       ... who are we kidding we'll never need this bahahahah.
def send_twitch(event)
  lists = ["N++", "N+", "N", "Nv2"].map{ |name|
    Twitch::GAME_IDS.key?(name) ? [name, Twitch::get_twitch_streams(name)] : nil
  }.compact.to_h
  event << "Currently active N related Twitch streams #{format_time}:"
  if lists.map{ |k, v| v.size }.sum == 0
    event << "None :shrug:"
  else
    lists.each{ |game, list|
      if list.size > 0
        event << "**#{game}**: #{list.size}"
        streams = list.take(20).map{ |stream| Twitch::format_stream(stream) }.join("\n")
        event << "```" + Twitch::table_header + "\n" + streams + "```"
      end
    }
  end
end

# Add role to player (internal, for permission system, not related to Discord roles)
def add_role(event)
  perm = assert_permissions(event, ['botmaster'])

  msg  = event.content
  user = parse_discord_user(msg)

  role = msg[/#{parse_term}/i, 2]
  raise "You need to provide a role in quotes." if role.nil?

  Role.add(user, role)
  event << "Added role \"#{role}\" to #{user.username}."
end

# Add custom player / level alias.
def add_alias(event)
  assert_permissions(event) # Only the botmaster can execute this
  
  msg = event.content
  aka = msg[/#{parse_term}/i, 2]
  raise "You need to provide an alias in quotes." if aka.nil?

  msg.remove!(/#{parse_term}/i)
  type   = !!msg[/\blevel\b/i] ? 'level' : (!!msg[/\bplayer\b/i] ? 'player' : nil)
  raise "You need to provide an alias type: level, player." if type.nil?

  entry = type == 'level' ? parse_level_or_episode(msg) : parse_player(msg, event.user.name)
  entry.add_alias(aka)
  event << "Added alias \"#{aka}\" to #{type} #{entry.name}."
end

# Send custom player / level aliases.
# ("type" has to be either 'level' or 'player' for now)
def send_aliases(event, page: nil, type: nil)
  # PARSE
  initial    = page.nil? && type.nil?
  reset_page = !type.nil?
  msg        = fetch_message(event, initial)
  type       = parse_alias_type(msg, type)
  page       = parse_page(msg, page, reset_page, event.message.components)
  case type
  when 'level'
    klass  = LevelAlias
    klass2 = :level
    name   = "`#{klass2.to_s.pluralize}`.`longname`"
  when 'player'
    klass  = PlayerAlias
    klass2 = :player
    name   = "`#{klass2.to_s.pluralize}`.`name`"
  else
    raise
  end

  # COMPUTE
  count   = klass.count.to_i
  pag     = compute_pages(count, page)
  aliases = klass.joins(klass2).order(:alias).offset(pag[:offset]).limit(PAGE_SIZE).pluck(:alias, name)

  # FORMAT
  pad     = aliases.map(&:first).map(&:length).max
  block   = aliases.map{ |a|
    name1 = pad_truncate_ellipsis(a[0], pad, 15)
    name2 = truncate_ellipsis(a[1], 35)
    "#{name1} #{name2}"
  }.join("\n")
  output  = "Aliases for #{type} names (total #{count}):\n#{format_block(block)}"

  # SEND
  view = Discordrb::Webhooks::View.new
  interaction_add_button_navigation(view, pag[:page], pag[:pages])
  interaction_add_select_menu_alias_type(view, type)
  send_message_with_interactions(event, output, view, !initial)
rescue
  event << 'Error fetching aliases.'
end

# Function to autogenerate screenshots of the userlevels for the dMMc contest
# in random palettes, zip them, and upload them.
def send_dmmc(event)
  assert_permissions(event, ['dmmc'])
  msg        = event.content.remove('dmmcize').strip
  limit      = 30
  levels     = Userlevel.where(Userlevel.sanitize("UPPER(title) LIKE ?", "%" + msg.upcase + "%")).to_a[0..limit - 1]
  count      = levels.count
  palettes   = Userlevel::THEMES.dup
  response   = nil
  zip_buffer = Zip::OutputStream.write_buffer{ |zip|
    levels.each_with_index{ |u, i|
      if i == 0
        response = event.channel.send_message("Creating screenshot 1 of #{count}...")
      else
        response.edit("Creating screenshot #{i + 1} of #{count}...")
      end
      palette = palettes.sample
      zip.put_next_entry(sanitize_filename(u.author) + ' - ' + sanitize_filename(u.title) + '.png')
      zip.write(u.screenshot(palette))
      palettes.delete(palette)
    }
  }
  zip = zip_buffer.string
  response.delete
  send_file(event, zip, 'dmmc.zip', true)
end

# Remove cheated / incorrect archives on command
# This can happen when scores get incorporated as archives before being ignored
# Should probably be restricted to botmasters
def sanitize_archives(event)
  assert_permissions(event)
  counts = Archive::sanitize
  event << "Sanitized database:"
  event << "* Removed #{counts['archive_del']} archives by ignored players." if counts.key?('archive_del')
  event << "* Removed #{counts['archive_ind_del']} individual archives." if counts.key?('archive_ind_del')
  event << "* Removed #{counts['orphan_demos']} orphaned demos." if counts.key?('orphan_demos')
end

def testa(event)
  golds = Score.where(rank: 0, highscoreable_type: 'Level')
               .joins("INNER JOIN levels ON levels.id = scores.highscoreable_id")
               .joins("INNER JOIN archives ON archives.replay_id = scores.replay_id")
               .where("archives.gold > -1")
               .order('archives.framecount')
               .pluck('levels.name', 'archives.framecount', 'archives.gold')
  event << format_block(golds.take(20).map{ |name, frames, gold|
    "#{name.ljust(10)} #{frames}"
  }.join("\n"))
  event << format_block(golds.reverse.take(20).map{ |name, frames, gold|
    "#{name.ljust(10)} #{frames}"
  }.join("\n"))
end

# TODO set level of the day on startup
def respond(event)
  msg = event.content

  # strip off the @inne++ mention, if present
  msg.sub!(/<@!?[0-9]*> */, '') # IDs might have an exclamation mark

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
    send_rankings(event)    if msg =~ /rank/i && msg !~ /history/i && msg !~ /table/i
    send_history(event)     if msg =~ /history/i && msg !~ /rank/i
    send_diff(event)        if msg =~ /diff/i
    send_community(event)   if msg =~ /community/i
    send_cleanliness(event) if msg =~ /cleanest/i || msg =~ /dirtiest/i
    send_ownages(event)     if msg =~ /ownage/i
    send_help(event)        if msg =~ /\bhelp\b/i || msg =~ /\bcommands\b/i
    send_help2(event)       if msg =~ /help2/i
    send_random(event)      if msg =~ /random/i
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
  send_points(event)         if msg =~ /\bpoints/i && msg !~ /history/i && msg !~ /rank/i && msg !~ /average/i && msg !~ /table/i && msg !~ /floating/i && msg !~ /legrange/i
  send_spreads(event)        if msg =~ /spread/i
  send_average_points(event) if msg =~ /\bpoints/i && msg !~ /history/i && msg !~ /rank/i && msg =~ /average/i && msg !~ /table/i && msg !~ /floating/i && msg !~ /legrange/i
  send_average_rank(event)   if msg =~ /average/i && msg =~ /rank/i && msg !~ /history/i && msg !~ /table/i && !!msg[NAME_PATTERN, 2]
  send_average_lead(event)   if msg =~ /average/i && msg =~ /lead/i && msg !~ /rank/i && msg !~ /table/i
  send_scores(event)         if msg =~ /scores/i && msg !~ /scoreshot/i && msg !~ /screenscores/i && msg !~ /shotscores/i && msg !~ /scorescreen/i && !!msg[NAME_PATTERN, 2]
  send_total_score(event)    if msg =~ /total\b/i && msg !~ /history/i && msg !~ /rank/i && msg !~ /table/i
  send_top_n_count(event)    if msg =~ /how many/i && msg !~ /point/i
  send_table(event)          if msg =~ /\btable\b/i
  send_comparison(event)     if msg =~ /\bcompare\b/i || msg =~ /\bcomparison\b/i
  send_stats(event)          if msg =~ /\bstat/i && msg !~ /generator/i && msg !~ /hooligan/i && msg !~ /space station/i
  send_screenshot(event)     if msg =~ /screenshot/i
  send_screenscores(event)   if msg =~ /screenscores/i || msg =~ /shotscores/i
  send_scoreshot(event)      if msg =~ /scoreshot/i || msg =~ /scorescreen/i
  send_suggestions(event)    if msg =~ /worst/i && msg !~ /nightmare/i
  send_list(event)           if msg =~ /\blist\b/i && msg !~ /of inappropriate words/i
  send_missing(event)        if msg =~ /missing/i
  send_maxable(event)        if msg =~ /maxable/i && msg !~ /rank/i && msg !~ /table/i
  send_maxed(event)          if msg =~ /maxed/i && msg !~ /rank/i && msg !~ /table/i
  send_level_name(event)     if msg =~ /\blevel name\b/i
  send_level_id(event)       if msg =~ /\blevel id\b/i
  send_analysis(event)       if msg =~ /analysis/i
  send_splits(event)         if msg =~ /\bsplits\b/i
  identify(event)            if msg =~ /my name is/i
  add_steam_id(event)        if msg =~ /my steam id is/i
  add_display_name(event)    if msg =~ /my display name is/i
  send_videos(event)         if msg =~ /\bvideo\b/i || msg =~ /\bmovie\b/i
  send_challenges(event)     if msg =~ /\bchallenges\b/i
  send_unique_holders(event) if msg =~ /\bunique holders\b/i
  send_twitch(event)         if msg =~ /\btwitch\b/i
  add_role(event)            if msg =~ /\badd\s*role\b/i
  send_aliases(event)        if msg =~ /\baliases\b/i
  add_alias(event)           if msg =~ /\badd\s*(level|player)?\s*alias\b/i
  send_dmmc(event)           if msg =~ /\bdmmcize\b/i
  sanitize_archives(event)   if msg =~ /\bsanitize archives\b/
  send_query(event)          if msg =~ /\bsearch\b/i || msg =~ /\bbrowse\b/i
  faceswap(event)            if msg =~ /faceswap/i
  #testa(event) if msg =~ /testa/i

rescue RuntimeError => e
  # Exceptions raised in here are user error, indicating that we couldn't
  # figure out what they were asking for, so send the error message out
  # to the channel
  event << e
end
