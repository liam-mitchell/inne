require 'ascii_charts'
require 'gruff'
require 'zip'

require_relative 'constants.rb'
require_relative 'utils.rb'
require_relative 'io.rb'
require_relative 'models.rb'
require_relative 'userlevels.rb'

# Prints COUNT of scores with specific characteristics for a player.
#   Arg 'file':    Also return list of scores in a text file.
#   Arg 'missing': Return complementary list, i.e., those NOT verifying conditions
#   Arg 'third':   Allows to parse player name using 'is'
def send_list(event, file = true, missing = false, third = false)
  # Parse message parameters
  msg     = event.content
  player  = parse_player(msg, event.user.name, false, false, false, false, third)
  msg     = msg.remove!(player.name)
  mappack = parse_mappack(msg)
  board   = parse_board(msg, 'hs')
  type    = parse_type(msg)
  tabs    = parse_tabs(msg)
  cool    = mappack.nil? ? parse_cool(msg) : false
  star    = mappack.nil? ? parse_star(msg) : false
  range   = parse_range(msg, cool || star || missing)
  ties    = parse_ties(msg)
  tied    = parse_tied(msg)
  sing    = (missing ? -1 : 1) * parse_singular(msg)

  # The range must make sense
  if !range[2]
    event << "You specified an empty range! (#{format_range(range[0], range[1])})"
    return
  end

  # Retrieve score count with specified characteristics
  if sing != 0
    list = player.singular(type, tabs, sing == 1 ? false : true)
  else
    list = player.range_ns(range[0], range[1], type, tabs, ties, tied, cool, star, missing, mappack, board)
  end

  # Format response
  max1     = find_max(:rank, type, tabs, false, mappack, board)
  max2     = player.range_ns(range[0], range[1], type, tabs, ties, tied).count
  full     = !missing || !(cool || star) # max is all scores, not all player's scores
  high     = missing && !(sing != 0 || cool || star) # list of highscoreables, not scores
  max      = full ? max1 : max2
  type     = format_type(type).downcase
  tabs     = format_tabs(tabs)
  range    = format_range(range[0], range[1], sing != 0 || board == 'gm')
  sing     = format_singular((missing ? -1 : 1) * sing)
  cool     = format_cool(cool)
  star     = format_star(star)
  ties     = format_ties(ties)
  tied     = format_tied(tied)
  boardB   = !mappack.nil? ? format_board(board) : ''
  mappackB = format_mappack(mappack)
  count    = list.count

  # Print count and possibly export list in file
  event << "#{player.print_name} #{missing ? 'is missing' : 'has'} #{count} out of #{max} #{cool} #{tied} #{boardB} #{tabs} #{type} #{range}#{star} #{sing} scores #{ties} #{mappackB}".squish + '.'
  if file
    list = list.map{ |s| high ? s : format_list_score(s, !mappack.nil? ? board : nil) }.join("\n")
    if count <= 20
      event << format_block(list)
    else
      send_file(event, list, "scores-#{player.sanitize_name}.txt", false)
    end
  end
rescue RuntimeError
  raise
rescue => e
  lex(e, 'Failed to send list of scores')
end

# Return list of players sorted by a number of different ranking types
# Navigation controls are optional
# The named parameters are ALL for the navigation:
#   'page'  Controls the page of the rankings button navigation
#   'type'  Type buttons (i.e., Level, Episode, Story)
#   'tab'   Tab select menu option (All, SI, S, SU, SL, ?, !)
#   'rtype' Ranking type select menu option
#   'ties'  Ties button
# When a named parameter is not nil, then that button/select menu was pressed,
# so it takes preference, and is used instead of parsing it from the message
def send_rankings(event, page: nil, type: nil, tab: nil, rtype: nil, ties: nil)
  # PARSE ranking parameters (from function arguments and message)
  initial    = page.nil? && type.nil? && tab.nil? && rtype.nil? && ties.nil?
  reset_page = !type.nil? || !tab.nil? || !rtype.nil? || !ties.nil?
  msg   = fetch_message(event, initial)
  tabs  = parse_tabs(msg, tab)
  tab   = tabs.empty? ? 'all' : (tabs.size == 1 ? tabs[0].to_s.downcase : 'tab')
  ties  = !ties.nil? ? ties : parse_ties(msg, rtype)
  play  = parse_many_players(msg)
  nav   = parse_nav(msg) || !initial
  full  = parse_global(msg) || parse_full(msg) || nav
  cool  = !rtype.nil? && parse_cool(rtype) || rtype.nil? && parse_cool(msg)
  star  = !rtype.nil? && parse_star(rtype, false, true) || rtype.nil? && parse_star(msg)
  maxed = !rtype.nil? && parse_maxed(rtype) || rtype.nil? && parse_maxed(msg)
  maxable = !maxed && (!rtype.nil? && parse_maxable(rtype) || rtype.nil? && parse_maxable(msg))
  rtype2 = rtype # save a copy before we change it
  rtype = rtype || parse_rtype(msg)
  whole = [
    'average_point',
    'average_rank',
    'point',
    'score',
    'cool',
    'star',
    'maxed',
    'maxable'
  ].include?(rtype) # default rank is top20, not top1 (0th)
  range = !parse_rank(rtype).nil? ? [0, parse_rank(rtype), true] : parse_range(rtype2.nil? ? msg : '', whole)
  rtype = fix_rtype(rtype, range[1])
  type  = parse_type(msg, type, true, initial, rtype == 'score' ? 'Level' : nil)
  mappack = parse_mappack(msg)
  board = parse_board(msg)

  raise "#{format_board(board)} rankings aren't available yet" if ['gm', 'dual'].include?(board)

  # The range must make sense
  if !range[2]
    event << "You specified an empty range! (#{format_range(range[0], range[1])})"
    return
  end

  # Determine ranking type and max value of said ranking
  rtag = :rank
  case rtype
  when 'average_point'
    rtag  = :avg_points
    max   = find_max(:avg_points, type, tabs, !initial, mappack, board)
  when 'average_top1_lead'
    rtag  = :avg_lead
    max   = nil
  when 'average_rank'
    rtag  = :avg_rank
    max   = find_max(:avg_rank, type, tabs, !initial, mappack, board)
  when 'point'
    rtag  = :points
    max   = find_max(:points, type, tabs, !initial, mappack, board)
  when 'score'
    rtag  = :score
    max   = find_max(:score, type, tabs, !initial, mappack, board)
  when 'singular_top1'
    rtag  = :singular
    max   = find_max(:rank, type, tabs, !initial, mappack, board)
    range[1] = 1
  when 'plural_top1'
    rtag  = :singular
    max   = find_max(:rank, type, tabs, !initial, mappack, board)
    range[1] = 0
  when 'tied_top1'
    rtag  = :tied_rank
    max   = find_max(:rank, type, tabs, !initial, mappack, board)
  when 'maxed'
    rtag  = :maxed
    max   = find_max(:maxed, type, tabs, !initial, mappack, board)
  when 'maxable'
    rtag  = :maxable
    max   = find_max(:maxable, type, tabs, !initial, mappack, board)
  else
    rtag  = :rank
    max   = find_max(:rank, type, tabs, !initial, mappack, board)
  end

  # EXECUTE specific rankings
  rank = Score.rank(
    ranking: rtag,      # Ranking type.             Def: Regular scores.
    type:    type,      # Highscoreable type.       Def: Levels and episodes.
    tabs:    tabs,      # Highscoreable tabs.       Def: All tabs (SI, S, SU, SL, ?, !).
    players: play,      # Players to ignore.        Def: None.
    a:       range[0],  # Bottom rank of scores.    Def: 0th.
    b:       range[1],  # Top rank of scores.       Def: 19th.
    ties:    ties,      # Include ties or not.      Def: No.
    cool:    cool,      # Only include cool scores. Def: No.
    star:    star,      # Only include * scores.    Def: No.
    mappack: mappack,   # Mappack to do rankings.   Def: None.
    board:   board      # Highscore or speedrun.    Def: Highscore.
  )

  # PAGINATION
  pagesize = nav ? PAGE_SIZE : 20
  page = parse_page(msg, page, reset_page, event.message.components)
  pag  = compute_pages(rank.size, page, pagesize)

  # FORMAT message
  min   = "Minimum number of scores required: #{min_scores(type, tabs, !initial, range[0], range[1], star, mappack)}" if ['average_rank', 'average_point'].include?(rtype)
  # --- Header
  prange = ![ # Don't print range for these rankings
    'tied_top1',
    'singular_top1',
    'plural_top1',
    'average_top1_lead'
  ].include?(rtype)
  full    = format_full(full)
  cool    = format_cool(cool)
  maxed   = format_maxed(maxed)
  maxable = format_maxable(maxable)
  tabs    = format_tabs(tabs)
  typeB   = format_type(type, true).downcase
  range   = format_range(range[0], range[1], !prange)
  star    = format_star(star)
  rtypeB  = format_rtype(rtype, ties: ties, range: false, basic: true)
  max     = format_max(max, rtype == 'average_rank' || board == 'sr' && rtype == 'score')
  mappack = format_mappack(mappack)
  board   = !mappack.nil? ? format_board(board) : ''
  play    = !play.empty? ? ' without ' + play.map{ |p| "`#{p.print_name}`" }.to_sentence  : ''
  header  = "#{full} #{cool} #{maxed} #{maxable} #{board} #{tabs} #{typeB} #{range}#{star} #{rtypeB} #{mappack} #{max} #{play} #{format_time}:".squish
  header[0] = header[0].upcase
  header  = "Rankings - #{header}".squish
  # --- Rankings
  if rank.empty?
    rank = '```These boards are empty!```'
  else
    rank = rank[pag[:offset]...pag[:offset] + pagesize] if full.empty? || nav
    pad1 = rank.map{ |r| r[1].to_i.to_s.length }.max
    pad2 = rank.map{ |r| r[0].length }.max
    pad3 = rank.map{ |r| r[2].to_i.to_s.length }.max
    fmt  = rank[0][1].is_a?(Integer) ? "%#{pad1}d" : "%#{pad1 + 4}.3f"
    rank = rank.each_with_index.map{ |r, i|
      line = "#{Highscoreable.format_rank(pag[:offset] + i)}: #{format_string(r[0], pad2)} - #{fmt % r[1]}"
      line += " (%#{pad3}d)" % [r[2]] if !r[2].nil?
      line
    }.join("\n")
    rank = format_block(rank)
  end
  # --- Footer
  rank.concat(min) if !min.nil? && (full.empty? || nav)

  # SEND message
  if nav
    view = Discordrb::Webhooks::View.new
    interaction_add_button_navigation(view, pag[:page], pag[:pages])
    interaction_add_type_buttons(view, type, ties)
    interaction_add_select_menu_rtype(view, rtype)
    interaction_add_select_menu_metanet_tab(view, tab)
    send_message_with_interactions(event, header + "\n" + rank, view, !initial)
  else
    length = header.length + rank.length
    event << header
    length < DISCORD_LIMIT && full.empty? ? event << rank : send_file(event, rank[4..-4], 'rankings.txt')
  end
rescue RuntimeError
  raise
rescue => e
  lex(e, 'Failed to perform the rankings')
  nil
end

# Sort highscoreables by amount of scores (0-20) with certain characteristics
# (e.g. classify levels by amount of cool/* scores)
def send_tally(event)
  # Parse message parameters
  msg   = event.content
  type  = parse_type(msg)
  tabs  = parse_tabs(msg)
  cool  = parse_cool(msg)
  star  = parse_star(msg)
  ties  = parse_ties(msg)
  range = parse_range(msg, true)
  list  = !!msg[/\blist\b/i]

  # Retrieve tally
  res   = Score.tally(list, type, tabs, ties, cool, star, range[0], range[1])
  count = list ? res.map(&:size).sum : res.sum

  # Format response
  type  = format_type(type)
  tabs  = format_tabs(tabs)
  cool  = format_cool(cool)
  star  = format_star(star)
  ties  = ties ? 'tied for 0th' : ''
  pad1  = (0..20).select{ |r| list ? !res[r].empty? : res[r] > 0 }.max.to_s.length
  pad2  = res.max.to_s.length if !list
  block = (0..20).to_a.reverse.map{ |r|
    if list
      "#{r} #{cplural('score', r)}:\n\n" + res[r].join("\n") + "\n" if !res[r].empty?
    else
      "#{"%#{pad1}d #{cplural('score', r, true)}: %#{pad2}d" % [r, res[r]]}" if res[r] != 0
    end
  }.compact.join("\n")
  range = format_range(range[0], range[1])

  # Send response
  event << "#{tabs} #{type} #{cool} #{range}#{star} scores #{ties} tally #{format_time}:".squish
  !list || count <= 20 ? event << format_block(block) : send_file(event, block, 'tally.txt')
end

# Return a player's total score (sum of scores) in specified tabs and type
def send_total_score(event)
  # Parse messsage parameters
  player = parse_player(event.content, event.user.name)
  type   = parse_type(event.content)
  tabs   = parse_tabs(event.content)

  # Retrieve total score
  score = player.total_score(type, tabs)

  # Format response
  max  = find_max(:score, type, tabs)
  type = format_type(type).downcase
  tabs = format_tabs(tabs)
  event << "#{player.print_name}'s total #{tabs} #{type} score is #{"%.3f" % [score]} out of #{"%.3f" % max}.".squish
end

# Return list of levels/episodes with largest/smallest score difference between
# 0th and Nth rank
def send_spreads(event)
  # Parse message parameters
  msg    = event.content
  n      = (parse_rank(msg) || 2) - 1
  type   = parse_type(msg) || Level
  tabs   = parse_tabs(msg)
  player = parse_player(msg, nil, false, true, false)
  small  = !!(msg =~ /smallest/)
  raise "I can't show you the spread between 0th and 0th..." if n == 0

  # Retrieve and format spreads
  spreads  = Highscoreable.spreads(n, type, tabs, small, player.nil? ? nil : player.id)
  namepad  = spreads.map{ |s| s[0].length }.max
  scorepad = spreads.map{ |s| s[1] }.max.to_i.to_s.length + 4
  spreads  = spreads.each_with_index
                    .map { |s, i| "#{"%02d" % i}: #{"%-#{namepad}s" % s[0]} - #{"%#{scorepad}.3f" % s[1]} - #{s[2]}"}
                    .join("\n")

  # Format response
  spread = small ? 'smallest' : 'largest'
  rank   = n.ordinalize
  type   = format_type(type).downcase.pluralize
  tabs   = tabs.empty? ? 'All ' : format_tabs(tabs)
  player = !player.nil? ? "owned by #{player.print_name} " : ''
  event << "#{tabs} #{type} #{player} with the #{spread} spread between 0th and #{rank}:".squish
  event << format_block(spreads)
end

# Send highscore leaderboard for a highscoreable.
#   'map'  means the highscoreable will be sent as a parameter, rather than
#          being parsed from the message (used, e.g., for lotd)
#   'ret'  means the leaderboards will be returned to be used in another
#          function (e.g., screenscores), rather than sent
#   'page' is used to navigate when there are multiple pages of matching levels
def send_scores(event, map = nil, ret = false, page: nil)
  # Parse message parameters
  initial = page.nil?
  msg     = fetch_message(event, initial)
  h       = map.nil? ? parse_level_or_episode(msg, partial: true, mappack: true) : map
  offline = parse_offline(msg)
  nav     = parse_nav(msg)
  mappack = h.is_a?(MappackHighscoreable)
  board   = parse_board(msg, 'hs', dual: true)
  board   = 'hs' if !mappack && board == 'dual'
  full    = parse_full(msg)
  raise "Sorry, Metanet levels only support highscore mode for now." if !mappack && board != 'hs'
  res     = ""
  #byebug

  # Navigating scores goes into a different method (see below this one)
  if !!msg[/nav((igat)((e)|(ing)))?\s*(high\s*)?scores/i] && !h.is_a?(MappackHighscoreable)
    send_nav_scores(event)
    return
  end

  # Multiple matches, send match list
  if h.is_a?(Array)
    format_level_matches(event, msg, page, initial, h, 'search')
    return
  end

  # Update scores, unless we're in offline mode or the connection fails
  if OFFLINE_STRICT
    res << "Strict offline mode is ON, sending local cached scores.\n"
  elsif !offline && h.is_a?(Downloadable) && h.update_scores == -1
    res << "Connection to the server failed, sending local cached scores.\n"
  end

  # Format scores
  header =  "#{format_full(full)} #{format_board(board).pluralize} for #{h.format_name}:".squish
  header[0] = header[0].upcase
  res << header
  scores = h.format_scores(mode: board, full: full, join: false)
  if full && scores.count > 20
    send_file(event, scores.join("\n"), "#{h.name}-scores.txt")
  else
    res << format_block(scores.join("\n"))
  end

  # Add cleanliness if it's an episode
  if h.is_a?(Episode)
    clean = round_score(h.cleanliness[1])
    res << "The cleanliness of this episode 0th is %.3f (%df)." % [clean, (60 * clean).round]
  end

  # Send response or return it
  if ret
    return res
  else
    event << res
  end

  # If it's an episode, update all 5 level scores in the background
  Thread.new { h.levels.each(&:update_scores) } if h.is_a?(Episode) && !offline && !OFFLINE_STRICT
rescue RuntimeError
  raise
rescue => e
  lex(e, 'Failed to send scores')
end

# Navigating scores: Main differences:
# - Does not update the scores.
# - Adds navigating between levels.
# - Adds navigating between dates.
def send_nav_scores(event, offset: nil, date: nil, page: nil)
  # Parse message parameters
  initial = offset.nil? && date.nil? && page.nil?
  msg     = fetch_message(event, initial)
  scores  = parse_level_or_episode(msg, partial: true)

  # Multiple matches, send match list
  if scores.is_a?(Array)
    format_level_matches(event, msg, page, initial, scores, 'search')
    return
  end

  # Single match, retrieve scores for specified date and highscoreable
  scores = scores.nav(offset.to_i)
  dates  = Archive.changes(scores).sort.reverse
  if initial || date.nil?
    new_index = 0
  else
    old_date  = event.message.components[1].to_a[2].custom_id.to_s.split(':').last.to_i
    new_index = (dates.find_index{ |d| d == old_date } + date.to_i).clamp(0, dates.size - 1)
  end
  date = dates[new_index] || 0

  # Format response
  str = "Navigating high scores for #{scores.format_name}:\n"
  str += format_block(Archive.format_scores(Archive.scores(scores, date), Archive.zeroths(scores, date))) rescue ""
  str += "*Warning: Navigating scores does not update them.*"

  # Send response
  view = Discordrb::Webhooks::View.new
  interaction_add_level_navigation(view, scores.name.center(11, ' '))
  interaction_add_date_navigation(view, new_index + 1, dates.size, date, date == 0 ? " " * 11 : Time.at(date).strftime("%Y-%b-%d"))
  send_message_with_interactions(event, str, view, !initial)
end

# Send a screenshot of a level/episode/story
#
# Prepared for navigation, but it's not possible to edit attachments for now,
# so commented that functionality, and 'offset' is not being used.
def send_screenshot(event, map = nil, ret = false, page: nil, offset: nil)
  # Parse message parameters
  initial = page.nil?
  msg     = fetch_message(event, initial)
  hash    = parse_palette(msg)
  msg     = hash[:msg]
  h       = map.nil? ? parse_level_or_episode(msg, partial: true, mappack: true) : map
  nav     = parse_nav(msg) || !initial
  
  # Multiple matches, send match list
  if h.is_a?(Array)
    format_level_matches(event, msg, page, initial, h, 'search')
    return
  end

  # Single match, retrieve screenshot
  #scores = scores.nav(offset.to_i)
  if h.is_a?(MappackHighscoreable)
    return event.send_message("Sorry, mappack episodes and stories don't have screenshots yet.") if !h.is_a?(MappackLevel)
    screenshot = h.screenshot(hash[:palette], file: true)
  else
    hash[:error] = "Sorry, Metanet levels are only available in the Classic palette.\n" if hash[:palette] != Map::DEFAULT_PALETTE
    name = h.name.upcase.gsub(/\?/, 'SS').gsub(/!/, 'SS2')
    filename = "screenshots/#{name}.jpg"

    if !File.exist?(filename)
      str = "I don't have a screenshot for #{h.format_name}... :("
      return [nil, str] if ret
      return event.send_message(str)
    end

    screenshot = File::open(filename)
  end
    
  # Send response
  str  = "#{hash[:error]}Screenshot for #{h.format_name}"
  file = screenshot
  return [file, str] if ret
  if nav
    # Attachments can't be modified so we're stuck for now
    send_message_with_interactions(event, str, nil, false, [file])
  else
    event << str
    event.attach_file(file)
  end
end

# One command to return a screenshot and then the scores,
# since it's a very common combination
def send_screenscores(event)
  # Parse message parameters
  msg = event.content
  map = parse_level_or_episode(msg, mappack: true)

  # Return both screenshot and scores, without sending them
  ss  = send_screenshot(event, map, true)
  s   = send_scores(event, map, true)

  # Send screenshot, if available
  if ss[0].nil?
    event.send_message(ss[1])
  else
    event.send_file(ss[0], caption: ss[1])
  end

  # Wait a bit to prevent an order change, and send scores
  sleep(0.05)
  event.send_message(s)
end

# Same, but sending the scores first and the screenshot second
def send_scoreshot(event)
  # Parse message parameters
  msg = event.content
  map = parse_level_or_episode(msg, mappack: true)

  # Retrieve both screenshot and scores, without sending them
  s   = send_scores(event, map, true)
  ss  = send_screenshot(event, map, true)

  # Send scores
  event.send_message(s)

  # Wait a bit to prevent an order change, and send screenshot, if available
  sleep(0.05)
  if ss[0].nil?
    event.send_message(ss[1])
  else
    event.send_file(ss[0], caption: ss[1])
  end
end

# Returns rank distribution of a player's scores, in both table and histogram form
def send_stats(event)
  # Parse message parameters
  msg    = event.content
  player = parse_player(msg, event.user.name)
  tabs   = parse_tabs(msg)
  ties   = parse_ties(msg)

  # Retrieve counts and generate table and histogram
  counts = player.score_counts(tabs, ties)

  full_counts = (0..19).map{ |r|
    l = counts[:levels][r].to_i
    e = counts[:episodes][r].to_i
    s = counts[:stories][r].to_i
    [l + e, l, e, s]
  }

  histogram = AsciiCharts::Cartesian.new(
    (0..19).map{ |r| [r, counts[:levels][r].to_i + counts[:episodes][r].to_i] },
    bar: true,
    hide_zero: true,
    max_y_vals: 15,
    title: 'Score histogram'
  ).draw

  # Format response
  totals  = full_counts.each_with_index.map{ |c, r| "#{Highscoreable.format_rank(r)}: #{"   %4d  %4d    %4d   %4d" % c}" }.join("\n\t")
  overall = "Totals:    %4d  %4d    %4d   %4d" % full_counts.reduce([0, 0, 0, 0]) { |sums, curr| sums.zip(curr).map { |a| a[0] + a[1] } }
  maxes   = [Level, Episode, Story].map{ |t| find_max(:rank, t, tabs) }
  maxes   = "Max:       %4d  %4d    %4d   %4d" % maxes.unshift(maxes[0] + maxes[1])
  tabs    = tabs.empty? ? "" : " in the #{format_tabs(tabs)} #{tabs.length == 1 ? 'tab' : 'tabs'}"
  msg1    = "Player high score counts for #{player.print_name}#{tabs}:\n```        Overall Level Episode Column\n\t#{totals}\n#{overall}\n#{maxes}"
  msg2    = "#{histogram}```"

  # Send response (careful, it can go over the char limit)
  if msg1.length + msg2.length <= DISCORD_LIMIT
    event << msg1
    event << msg2
  else
    event.send_message(msg1 + "```")
    event.send_message("```" + msg2)
  end
end

# Returns community's overal total and average scores
#   * The total score is the sum of all 0th scores
#   * The average score is the total score over the number of scores
#   * The difference between level and episode scores is computed by adding
#     the 5 corresponding level 0ths, subtracting the 4 * 90 additional
#     seconds one gets at the start of each individual level (bar level 0),
#     and then subtracting the episode 0th score.
def send_community(event)
  # Parse message parameters
  msg  = event.content
  tabs = parse_tabs(msg)
  cond = !(tabs&[:SS, :SS2]).empty? || tabs.empty?

  # Retrieve community's total and average scores
  levels = Score.total_scores(Level, tabs, true)
  episodes = Score.total_scores(Episode, tabs, false)
  levels_no_secrets = (cond ? Score.total_scores(Level, tabs, false) : levels)
  difference = levels_no_secrets[0] - 4 * 90 * episodes[1] - episodes[0]

  # Format response
  pad = ("%.3f" % levels[0]).length
  str = ''
  str << "Total level score (TLS):   #{"%#{pad}.3f" % levels[0]}\n"
  str << "Total episode score (TES): #{"%#{pad}.3f" % episodes[0]}\n"
  str << "TLS (w/o secrets):         #{"%#{pad}.3f" % levels_no_secrets[0]}\n" if cond
  str << "Difference (TLS - TES):    #{"%#{pad}.3f" % [difference]}\n\n"
  str << "Average level score:       #{"%#{pad}.3f" % [levels[0]/levels[1]]}\n"
  str << "Average episode score:     #{"%#{pad}.3f" % [episodes[0]/episodes[1]]}\n"
  str << "Average difference:        #{"%#{pad}.3f" % [difference/episodes[1]]}\n"
  event << "Community's total #{format_tabs(tabs)} scores #{format_time}:\n".squish
  event << format_block(str)
end

# Return list of levels/episodes sorted by number of ties for 0th (desc)
def send_maxable(event, maxed = false)
  # Parse message parameters
  msg    = event.content
  player = parse_player(msg, nil, false, true, false)
  type   = parse_type(msg) || Level
  tabs   = parse_tabs(msg)

  # Retrieve maxed/maxable scores
  ties   = Highscoreable.ties(type, tabs, player.nil? ? nil : player.id, maxed)
  ties   = ties.take(NUM_ENTRIES) if !maxed
  pad1   = ties.map{ |s| s[0].length }.max
  pad2   = ties.map{ |s| s[1].to_s.length }.max
  count  = ties.size
  ties   = ties.map { |s|
    if maxed
      "#{"%-#{pad1}s" % s[0]} - #{format_string(s[3])}"
    else
      "#{"%-#{pad1}s" % s[0]} - #{"%#{pad2}d" % s[1]} - #{format_string(s[3])}"
    end
  }.join("\n")

  # Format response
  type   = format_type(type).downcase
  tabs   = tabs.empty? ? 'All' : format_tabs(tabs)
  player = player.nil? ? '' : 'without ' + player.print_name
  if maxed
    footer = "There's a total of #{count} potentially maxed #{type.pluralize}."
    event << "#{tabs} potentially maxed #{type.pluralize} #{format_time} #{player}".squish + ":"
    if count <= 20
      event << format_block(ties) + footer
    else
      send_file(event, ties, "maxed-#{type.pluralize}.txt", false)
      event << footer
    end
  else
    event << "#{tabs} #{type.pluralize} with the most ties for 0th #{format_time} #{player}".squish + ":"
    event << format_block(ties)
  end
end

# Returns a list of maxed levels/episodes, i.e., with 20 ties for 0th
def send_maxed(event)
  send_maxable(event, true)
end

# Returns a list of episodes sorted by difference between
# episode 0th and the sum of the level 0ths
def send_cleanliness(event)
  # Parse message parameters
  msg   = event.content
  tabs  = parse_tabs(msg)
  clean = !!msg[/cleanest/i]

  # Retrieve episodes and cleanliness
  list = Episode.cleanliness(tabs).sort_by{ |e| (clean ? e[1] : -e[1]) }.take(NUM_ENTRIES)
  pad1 = list.map{ |e| e[0].length }.max
  pad2 = list.map{ |e| e[1].to_i.to_s.length + 4 }.max
  list = list.map{ |e| "#{"%#{pad1}s" % e[0]} - #{"%#{pad2}.3f" % e[1]} - #{e[2]}" }.join("\n")

  # Format response
  tabs = tabs.empty? ? 'All ' : format_tabs(tabs)
  event << "#{tabs} #{clean ? 'cleanest' : 'dirtiest'} episodes #{format_time}:".squish
  event << format_block(list)
end

# Returns a list of episode ownages, i.e., episodes where the same player
# has 0th in all 5 levels and the episode
def send_ownages(event)
  # Parse message parameters
  msg  = event.content
  tabs = parse_tabs(msg)

  # Retrieve ownages
  ownages = Episode.ownages(tabs)
  pad     = ownages.map{ |e, p| e.length }.max
  list    = ownages.map{ |e, p| "#{"%#{pad}s" % e} - #{p}" }.join("\n")
  count   = ownages.count
  if count <= 20
    block = list
  else
    block = ownages.group_by{ |e, p| p }.map{ |p, o| "#{format_string(p)} - #{o.count}" }.join("\n")
  end

  # Format response
  tabs_h = tabs.empty? ? 'All ' : format_tabs(tabs)
  tabs_f = tabs.empty? ? '' : format_tabs(tabs)
  event << "#{tabs_h} episode ownages #{format_max(find_max(:rank, Episode, tabs))} #{format_time}:".squish
  event << format_block(block) + "There're a total of #{count} #{tabs_f} episode ownages."
  send_file(event, list, 'ownages.txt') if count > 20
end

# Return list of a player's most improvable scores, filtered by type and tab
def send_suggestions(event)
  # Parse message parameters
  msg    = event.content
  player = parse_player(msg, event.user.name)
  type   = parse_type(msg)
  tabs   = parse_tabs(msg)
  cool   = parse_cool(msg)
  star   = parse_star(msg)
  range  = parse_range(msg, true)
  ties   = parse_ties(msg)

  # Retrieve and format most improvable scores
  list = player.improvable_scores(type, tabs, range[0], range[1], ties, cool, star)
  pad1 = list.map{ |level, gap| level.length }.max
  pad2 = list.map{ |level, gap| gap }.max.to_i.to_s.length + 4
  list = list.map{ |level, gap| "#{"%-#{pad1}s" % [level]} - #{"%#{pad2}.3f" % [gap]}" }.join("\n")

  # Send response
  tabs  = format_tabs(tabs)
  type  = format_type(type).downcase
  cool  = format_cool(cool)
  star  = format_star(star)
  range = format_range(range[0], range[1])
  ties  = format_ties(ties)
  event << "Most improvable #{cool} #{star} #{tabs} #{type} #{range} scores #{ties} for #{player.print_name}:".squish
  event << format_block(list)
end

# Return level ID for a specified level name
# The parameter 'page' is for button page navigation when there are many results
def send_level_id(event, page: nil)
  # Parse message parameters
  initial = page.nil?
  msg     = fetch_message(event, initial)
  level   = parse_level_or_episode(msg, partial: true)

  # Multiple matches, send match list
  if level.is_a?(Array)
    format_level_matches(event, msg, page, initial, level, 'search')
    return
  end

  # Single match, send ID if it's a level
  raise "Episodes and stories don't have a name!" if level.is_a?(Episode) || level.is_a?(Story)
  event << "#{level.longname} is level #{level.name}."
end

# Return level name for a specified level ID
def send_level_name(event)
  level = parse_level_or_episode(event.content.gsub(/level/, ""))
  raise "Episodes and stories don't have a name!" if level.is_a?(Episode) || level.is_a?(Story)
  event << "#{level.name} is called #{level.longname}."
end

# Return a player's point count
#   (a 0th is worth 20 points, a 1st is 19 points, all the way down to
#    1 point for a 19th score)
# Arguments:
#   'avg'  we compute the average points, see method below
#   'rank' we compute the average rank, which is just 20 - avg points
def send_points(event, avg = false, rank = false)
  # Parse message parameters
  msg    = event.content
  player = parse_player(msg, event.user.name)
  type   = parse_type(msg)
  tabs   = parse_tabs(msg)

  # Retrieve player points, filtered by type and tabs
  points = avg ? player.average_points(type, tabs) : player.points(type, tabs)

  # Format and send response
  max  = find_max(avg ? :avg_points : :points, type, tabs)
  type = format_type(type).downcase
  tabs = format_tabs(tabs)
  if avg
    if rank
      event << "#{player.print_name} has an average #{tabs} #{type} rank of #{"%.3f" % [20 - points]}.".squish
    else
      event << "#{player.print_name} has #{"%.3f" % [points]} out of #{"%.3f" % max} average #{tabs} #{type} points.".squish
    end
  else
    event << "#{player.print_name} has #{points} out of #{max} #{tabs} #{type} points.".squish
  end
end

# Return a player's average point count
# (i.e., total points divided by the number of scores, measures score quality)
def send_average_points(event)
  send_points(event, true)
end

# Return a player's average rank across all their scores, ideal quality measure
# It's actually just 20 - average points
def send_average_rank(event)
  send_points(event, true, true)
end

# Return a player's average 0th lead across all their 0ths
def send_average_lead(event)
  # Parse message parameters
  msg    = event.content
  player = parse_player(msg, event.user.name)
  type   = parse_type(msg) || Level
  tabs   = parse_tabs(msg)

  # Retrieve average 0th lead
  average = player.average_lead(type, tabs)

  # Format and send response
  type = format_type(type).downcase
  tabs = format_tabs(tabs)
  event << "#{player.print_name} has an average #{type} #{tabs} lead of #{"%.3f" % [average]}.".squish
end

# Return a table containing a certain measure (e.g. top20 count, points, etc)
# and classifying it by type (columns) and tabs (rows)
def send_table(event)
  # Parse message parameters
  msg    = event.content
  player = parse_player(msg, event.user.name)
  cool   = parse_cool(msg)
  star   = parse_star(msg)
  global = false # Table for a user, or the community
  ties   = parse_ties(msg)
  avg    = !!(msg =~ /\baverage\b/i) || !!(msg =~ /\bavg\b/i)
  rtype = :rank
  if avg
    if msg   =~ /\bpoint\b/i
      rtype  = :avg_points
      header = "average points"
    else
      rtype  = :avg_rank
      header = "average rank"
    end
  elsif msg  =~ /\bpoint/i
    rtype    = :points
    header   = "points"
  elsif msg  =~ /\bscore/i
    rtype    = :score
    header   = "total scores"
  elsif msg  =~ /\btied\b/i
    rtype    = :tied_rank
    header   = "tied scores"
  elsif msg  =~ /\bmaxed/i
    rtype    = :maxed
    header   = "maxed scores"
    global   = true
  elsif msg  =~ /\bmaxable/i
    rtype    = :maxable
    header   = "maxable scores"
    global   = true
  else
    rtype    = :rank
    header   = "scores"
  end
  range = parse_range(msg, cool || star || rtype != :rank)

  # The range must make sense
  if !range[2]
    event << "You specified an empty range! (#{format_range(range[0], range[1])})"
    return
  end
  
  # Retrieve table (a matrix, first index is type, second index is tab)
  table = player.table(rtype, ties, range[0], range[1], cool, star)

  # Construct table. If it's an average measure, we need to retrieve the
  # table of totals first to do the weighed averages.
  if avg
    scores = player.table(:rank, ties, 0, 20)
    totals = Level::tabs.select{ |tab, id| id < 7 }.map{ |tab, id|
      lvl = scores[0][tab] || 0
      ep  = scores[1][tab] || 0
      [format_tab(tab.to_sym), lvl, ep, lvl + ep]
    }
  end
  table = Level::tabs.select{ |tab, id| id < 7 }.each_with_index.map{ |tab, i|
    lvl = table[0][tab[0]] || 0
    ep  = table[1][tab[0]] || 0
    [
      format_tab(tab[0].to_sym),
      avg ? lvl : round_score(lvl),
      avg ? ep : round_score(ep),
      avg ? wavg([lvl, ep], totals[i][1..2]) : round_score(lvl + ep)
    ]
  }

  # Format table rows
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

  # Send response
  cool  = format_cool(cool)
  star  = format_star(star)
  ties  = format_ties(ties)
  range = format_range(range[0], range[1], [:maxed, :maxable].include?(rtype))
  header = "#{cool} #{range}#{star} #{header} #{ties} table".squish
  player = global ? "" : "#{player.format_name.strip}'s "
  event << "#{player} #{global ? header.capitalize : header} #{format_time}:".squish
  event << format_block(make_table(rows))
end

# Return score comparison between 2 players. Lists 5 categories:
#   Scores which only P1 has
#   Scores where P1 > P2
#   Scores where P1 = P2
#   Scores where P1 < P2
#   Scores which only P2 has
# Returns both the counts, as well as the list of scores in a file
def send_comparison(event)
  # Parse message parameters
  msg    = event.content
  type   = parse_type(msg)
  tabs   = parse_tabs(msg)
  p1, p2 = parse_players(msg, event.user.name)

  # Retrieve comparison info
  comp   = Player.comparison(type, tabs, p1, p2)
  counts = comp.map{ |t| t.map{ |r, s| s.size }.sum }

  # Format message
  header = "#{format_type(type)} #{format_tabs(tabs)} comparison between #{p1.truncate_name} and #{p2.truncate_name} #{format_time}:".squish
  rows = ["Scores with only #{p1.truncate_name}"]
  rows << "Scores where #{p1.truncate_name} > #{p2.truncate_name}"
  rows << "Scores where #{p1.truncate_name} = #{p2.truncate_name}"
  rows << "Scores where #{p1.truncate_name} < #{p2.truncate_name}"
  rows << "Scores with only #{p2.truncate_name}"
  table = rows.zip(counts)
  pad1  = table.map{ |row, count| row.length }.max
  pad2  = table.map{ |row, count| numlen(count, false) }.max
  table = table.map{ |r, c| "#{"%-#{pad1}s" % r} - #{"%#{pad2}d" % c}" }.join("\n")

  # Format file
  list = (0..4).map{ |i|
    pad1 = comp[i].map{ |r, s| s.map{ |e| e.size == 2 ?  e[0][2].length :  e[2].length }.max }.max
    pad2 = comp[i].map{ |r, s| s.map{ |e| e.size == 2 ? numlen(e[0][3]) : numlen(e[3]) }.max }.max
    pad3 = comp[i].map{ |r, s| s.map{ |e| e.size == 2 ? numlen(e[1][3]) : numlen(e[3]) }.max }.max
    rows[i] + ":\n\n" + comp[i].map{ |r, s|
      s.map{ |e|
        if e.size == 2
          str = "#{"%-#{pad1}s" % e[0][2]} - "
          str += "[#{"%02d" % e[0][0]}: #{"%#{pad2}.3f" % e[0][3]}] vs. "
          str += "[#{"%02d" % e[1][0]}: #{"%#{pad3}.3f" % e[1][3]}]"
          str
        else
          "#{"%02d" % e[0]}: #{"%-#{pad1}s" % e[2]} - #{"%#{pad2}.3f" % e[3]}"
        end
      }.join("\n")
    }.join("\n") + "\n"
  }.join("\n")

  # Send response
  event << header + format_block(table)
  send_file(event, list, "comparison-#{p1.sanitize_name}-#{p2.sanitize_name}.txt")
end

# Return a list of random highscoreables
def send_random(event)
  # Parse message parameters
  msg    = event.content
  type   = parse_type(msg) || Level
  tabs   = parse_tabs(msg)
  amount = [msg[/\d+/].to_i || 1, NUM_ENTRIES].min

  # Retrieve list of maps
  maps = tabs.empty? ? type.all : type.where(tab: tabs)

  # Format and send response
  if amount > 1
    tabs = format_tabs(tabs)
    type = format_type(type).downcase.pluralize
    event << "Random selection of #{amount} #{tabs} #{type}:".squish
    event << format_block(maps.sample(amount).map(&:name).join("\n"))
  else
    map = maps.sample
    send_screenshot(event, map)
  end
end

# Return list of challenges for specified level, ordered and formatted as in the game
# 'page' parameters controls button page navigation when there are many results
def send_challenges(event, page: nil)
  # Parse message parameters
  initial = page.nil?
  msg     = fetch_message(event, initial)
  lvl     = parse_level_or_episode(msg, partial: true)

  # Multiple matches, send match list
  if lvl.is_a?(Array)
    format_level_matches(event, msg, page, initial, lvl, 'search')
    return
  end

  # Single match, send challenge list if it's a non-secret level
  raise "#{lvl.class.to_s.pluralize.capitalize} don't have challenges!" if lvl.class != Level
  raise "#{lvl.tab.to_s} levels don't have challenges!" if ["SI", "SL"].include?(lvl.tab.to_s)
  event << "Challenges for #{lvl.longname} (#{lvl.name}):\n#{format_block(lvl.format_challenges)}"
end

# Return list of matches for specific level name query
# Also the fallback for other functions when there are multiple matches
# (e.g. scores, screenshot, challenges, level id, ...)
# 'page' parameters controls button page navigation when there are many results
def send_query(event, page: nil)
  initial = page.nil?
  msg     = fetch_message(event, initial)
  lvl     = parse_level_or_episode(msg, partial: true, array: true)
  format_level_matches(event, msg, page, initial, lvl, 'search')
end

# Auxiliar function called during lotd/eotw/cotm
# Can also be called on demand by the botmaster
def send_diff(event)
  type = parse_type(event.content) || Level
  current = GlobalProperty.get_current(type)
  old_scores = GlobalProperty.get_saved_scores(type)
  since = (type == Level ? "yesterday" : (type == Episode ? "last week" : "last month"))

  diff = current.format_difference(old_scores)
  event << "Score changes on #{current.format_name} since #{since}:\n```#{diff}```"
end

# Auxiliar function used by the demo analysis method
def do_analysis(scores, rank)
  run      = scores.scores[rank]
  return nil if run.nil?
  analysis = run.demo.decode
  {
    'player'   => run.player.name,
    'scores'   => scores.format_name,
    'rank'     => "%02d" % rank,
    'score'    => "%.3f" % run.score,
    'analysis' => analysis,
    'gold'     => "%.0f" % [(run.score + analysis.size.to_f / 60 - 90) / 2]
  }
end

# Return the demo analysis of a level's replay
def send_analysis(event)
  # Parse message parameters
  msg    = event.content
  ranks  = parse_ranks(msg)
  scores = parse_level_or_episode(msg)
  raise "Episodes and columns can't be analyzed (yet)" if scores.is_a?(Episode) || scores.is_a?(Story)

  # Perform demo analysis
  analysis = ranks.map{ |rank| do_analysis(scores, rank) }.compact
  length   = analysis.map{ |a| a['analysis'].size }.max
  raise "Connection failed" if !length || length == 0
  padding  = Math.log(length, 10).to_i + 1
  head     = " " * padding + "|" + "LJR|" * analysis.size
  sep      = "-" * head.size

  # We format the result in 3 different ways, only 2 are being used though.
  # Format 1 example:
  #   R.R.R.JR.JR...
  raw_result = analysis.map{ |a|
    a['analysis'].map{ |b|
      [b % 2 == 1, b / 2 % 2 == 1, b / 4 % 2 == 1]
    }.map{ |f|
      frame = ""
      if f[2] then frame.concat("l") end
      if f[0] then frame.concat("j") end
      if f[1] then frame.concat("r") end
      frame
    }.join(".")
  }.join("\n\n")

  # Format 2 example:
  #       |JRL|
  #   ---------
  #   0001| > |
  #   0002| > |
  #   0003| > |
  #   0004|^> |
  #   0005|^> |
  #   ...
  table_result = analysis.map{ |a|
    table = a['analysis'].map{ |b|
      [
        b / 4 % 2 == 1 ? "<" : " ",
        b     % 2 == 1 ? "^" : " ",
        b / 2 % 2 == 1 ? ">" : " "
        
      ].push("|")
    }
    while table.size < length do table.push([" ", " ", " ", "|"]) end
    table.transpose
  }.flatten(1)
   .transpose
   .each_with_index
   .map{ |l, i| "%0#{padding}d|#{l.join}" % [i + 1] }
   .insert(0, head)
   .insert(1, sep)
   .join("\n")

  # Format 3 example:
  #   >>>//...
  codes = [
    ['-',  'Nothing'        ],
    ['^',  'Jump'           ],
    ['>',  'Right'          ],
    ['/',  'Right Jump'     ],
    ['<',  'Left'           ],
    ['\\', 'Left Jump'      ],
    ['≤',  'Left Right'     ],
    ['|',  'Left Right Jump']
  ]
  key_result = analysis.map{ |a|
    a['analysis'].map{ |f|
      codes[f][0] || '?' rescue '?'
    }.join
     .scan(/.{,60}/)
     .reject{ |f| f.empty? }
     .each_with_index
     .map{ |f, i| "%0#{padding}d #{f}" % [60 * i] }
     .join("\n")
  }.join("\n\n")

  # Format response
  #   - Digest of runs' properties (length, score, gold collected, etc)
  pad = analysis.map{ |a| a['player'].length }.max
  properties = format_block(
    analysis.map{ |a|
      "#{a['rank']}: #{format_string(a['player'], pad)} - #{a['score']} [#{a['analysis'].size}f, #{a['gold']}g]"
    }.join("\n")
  )
  #  - Summary of symbols' meaning
  explanation = "[#{codes.map{ |code, meaning| "**#{Regexp.escape(code)}** #{meaning}" }.join(', ')}]"
  #  - Header of message, and final result (format 2 only used if short enough)
  header = "Replay analysis for #{scores.format_name} #{format_time}.".squish
  result = "#{header}\n#{properties}"
  result += "#{explanation}#{format_block(key_result)}" unless analysis.sum{ |a| a['analysis'].size } > 1080

  # Send response
  event << result
  send_file(event, table_result, "analysis-#{scores.name}.txt")
end

def send_demo_download(event)
  msg    = event.content
  h      = parse_level_or_episode(msg)
  rank   = [parse_range(msg).first, h.scores.size - 1].min
  score  = h.scores[rank]
  event << "Downloading #{score.player.name}'s #{rank.ordinalize} score in #{h.name} (#{"%.3f" % [score.score]}):"
  send_file(event, score.demo.demo, "#{h.name}_#{rank.ordinalize}_replay", true)
end

# Use SimVYo's tool to trace the replay of a run based on the map data and
# the demo data.
def send_trace(event)
  assert_permissions(event, ['ntrace'])
  raise "Sorry, tracing is disabled." if !FEATURE_NTRACE
  wait_msg = event.send_message("Waiting for another trace to finish...") if $mutex[:ntrace].locked?
  $mutex[:ntrace].synchronize do
    wait_msg.delete if !wait_msg.nil?
    level = parse_level_or_episode(event.content, mappack: true)
    raise "Episodes and columns can't be traced" if !level.is_a?(Levelish)
    map = !level.is_a?(Map) ? MappackLevel.find_by(id: level.id) : level
    raise "Level data not found" if map.nil?
    map.trace(event)
  end
end

# Return an episode's partial level scores and splits using 2 methods:
#   1) The actual episode splits, using SimVYo's tool
#   2) The IL splits
# Also return the differences between both
def send_splits(event)
  # Parse message parameters
  msg = event.content
  ep = parse_level_or_episode(msg, mappack: true)
  ep = ep.episode if ep.is_a?(Levelish)
  raise "Sorry, columns can't be analyzed yet." if ep.is_a?(Storyish)
  mappack = ep.is_a?(MappackHighscoreable)
  board = parse_board(msg, 'hs')
  raise "Sorry, speedrun mode isn't available for Metanet levels yet." if !mappack && board == 'sr'
  raise "Sorry, episode splits are only available for either highscore or speedrun mode" if !['hs', 'sr'].include?(board)
  scores = ep.leaderboard(board, pluck: false)
  rank = parse_range(msg)[0].clamp(0, scores.size - 1)
  ntrace = board == 'hs' # Requires ntrace

  # Calculate episode splits
  if board == 'sr'
    valid = [true] * 5
    ep_scores = Demo.decode(scores[rank].demo.demo, true).map(&:size)
    ep_splits = splits_from_scores(ep_scores, start: 0, factor: 1, offset: 0)
  elsif FEATURE_NTRACE
    # Export input files
    File.binwrite('inputs_episode', scores[rank].demo.demo)
    ep.levels.each_with_index{ |l, i|
      map = !l.is_a?(Map) ? MappackLevel.find(l.id) : l
      File.binwrite("map_data_#{i}", map.dump_level)
    }
    system "python3 #{PATH_NTRACE}"

    # Read output files
    file = File.binread('output.txt') rescue nil
    raise "ntrace failed." if file.nil?
    valid = file.scan(/True|False/).map{ |b| b == 'True' }
    ep_splits = file.split(/True|False/)[1..-1].map{ |d|
      round_score(d.strip.to_i.to_f / 60.0)
    }
    ep_scores = scores_from_splits(ep_splits, offset: 90.0)
    FileUtils.rm(['inputs_episode', *Dir.glob('map_data_*'), 'output.txt'])
  end

  # Calculate IL splits
  lvl_splits = ep.splits(rank, board: board)
  if lvl_splits.nil?
    event << "Sorry, that rank doesn't seem to exist for at least some of the levels."
    return
  end
  scoref = !mappack ? 'score' : "score_#{board}"
  factor = mappack && board == 'hs' ? 60.0 : 1
  lvl_scores = ep.levels.map{ |l| l.leaderboard(board)[rank][scoref] / factor }

  # Calculate differences
  full = !ntrace || FEATURE_NTRACE

  if full
    errors = valid.count(false)
    if errors > 0
      wrong = valid.each_with_index.map{ |v, i| !v ? i.to_s : nil }.compact.to_sentence
      word = "level#{errors > 1 ? 's' : ''}"
      event << "Warning: Couldn't calculate episode splits (error in #{word} #{wrong})."
      full = false
    end

    cum_diffs = lvl_splits.each_with_index.map{ |ls, i|
      mappack && board == 'sr' ? ep_splits[i] - ls : ls - ep_splits[i]
    }
    diffs = cum_diffs.each_with_index.map{ |d, i|
      round_score(i == 0 ? d : d - cum_diffs[i - 1])
    }
  end

  # Format response
  rows = []
  rows << ['', '00', '01', '02', '03', '04']
  rows << :sep
  rows << ['Ep splits', *ep_splits]  if full
  rows << ['Lvl splits', *lvl_splits]
  rows << ['Total diff', *cum_diffs]  if full
  rows << :sep                        if full
  rows << ['Ep scores',  *ep_scores]  if full
  rows << ['Lvl scores', *lvl_scores]
  rows << ['Ind diffs',   *diffs]       if full

  event << "#{rank.ordinalize} #{format_board(board)} splits for episode #{ep.name}:"
  event << "(Episode splits aren't available because ntrace is disabled)." if ntrace && !FEATURE_NTRACE
  event << format_block(make_table(rows))
rescue RuntimeError
  raise
rescue => e
  lex(e, 'Failed to calculate episode splits')
end

# Command to allow SimVYo to dynamically update his ntrace tool by sending the
# file via Discord
def update_ntrace(event)
  # Ensure only those allowed can do this
  assert_permissions(event, ['ntrace'])

  # Fetch attached file and perform integrity checks
  files = event.message.attachments.select{ |a| a.filename == 'ntrace.py' }
  raise "File `ntrace.py` not found in the attachments" if files.size == 0
  raise "Too many `ntrace.py` files found in the attachments" if files.size > 1
  file = files.first
  raise "The ntrace file provided is too big" if file.size > 1024 ** 2
  res = Net::HTTP.get(URI(file.url))
  raise "The received ntrace file is corrupt" if res.size != file.size

  # Update file
  old_date = File.mtime(PATH_NTRACE) rescue nil
  old_size = File.size(PATH_NTRACE) rescue nil
  File.binwrite(PATH_NTRACE, res)
  new_date = File.mtime(PATH_NTRACE) rescue nil
  new_size = File.size(PATH_NTRACE) rescue nil
  event << (new_date.nil? ? 'Failed to update ntrace.' : "ntrace updated successfully.")
  versions = ''
  versions << "Old version: #{old_date.strftime('%Y/%m/%d %H:%M:%S')} (#{old_size} bytes)\n" if !old_date.nil?
  versions << "New version: #{new_date.strftime('%Y/%m/%d %H:%M:%S')} (#{new_size} bytes)\n" if !new_date.nil?
  event << format_block(versions)

  ld("#{event.user.name} updated ntrace (#{new_size} bytes).")
rescue RuntimeError
  raise
rescue => e
  lex(e, 'Failed to update ntrace file')
end

# Sends a PNG graph plotting the evolution of player's scores (e.g. top20 count,
# 0th count, points...) over time.
# Currently unavailable because the db structure changed between CCS and Eddy
# See the subsequent method for the old code
def send_history(event)
  event << "Function not available yet, restructuring being done (since 2020 :joy:)."
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
  set_channels(event) if $channel.nil?
end

def thanks(event)
  event << "You're welcome!"
end

def faceswap(event)
  avatars    = Dir.entries("images/avatars").select{ |f| File.file?("images/avatars/" + f) }
  old_avatar = get_avatar
  new_avatar = old_avatar
  while new_avatar == old_avatar
    new_avatar = avatars.sample
  end
  File::open("images/avatars/" + new_avatar) do |f|
    $bot.profile.avatar = f
  end
rescue
  event << "Failed to change avatar, try again later. The avatar can only be changed 4 times every 10 minutes."
else
  set_avatar(new_avatar)
end

def send_level_time(event)
  next_level = GlobalProperty.get_next_update(Level) - Time.now
  next_level_hours = (next_level / (60 * 60)).to_i
  next_level_minutes = (next_level / 60).to_i - (next_level / (60 * 60)).to_i * 60

  event << "I'll post a new level of the day in #{next_level_hours} hours and #{next_level_minutes} minutes."
end

def send_episode_time(event)
  next_episode = GlobalProperty.get_next_update(Episode) - Time.now

  next_episode_days = (next_episode / (24 * 60 * 60)).to_i
  next_episode_hours = (next_episode / (60 * 60)).to_i - (next_episode / (24 * 60 * 60)).to_i * 24

  event << "I'll post a new episode of the week in #{next_episode_days} days and #{next_episode_hours} hours."
end

def send_story_time(event)
  next_story = GlobalProperty.get_next_update(Story) - Time.now

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
  event << "The current level of the day is #{GlobalProperty.get_current(Level).format_name}."
end

def send_episode(event)
  event << "The current episode of the week is #{GlobalProperty.get_current(Episode).format_name}."
end

def send_story(event)
  event << "The current column of the month is #{GlobalProperty.get_current(Story).format_name}."
end

def dump(event)
  assert_permissions(event)
  lotd = GlobalProperty.get_current(Level).format_name unless GlobalProperty.get_current(Level).nil?
  eotw = GlobalProperty.get_current(Episode).format_name unless GlobalProperty.get_current(Episode).nil?
  cotm = GlobalProperty.get_current(Story).format_name unless GlobalProperty.get_current(Story).nil?
  log("current level/episode/story: #{lotd.to_s}, #{eotw.to_s}, #{cotm.to_s}")
  score = GlobalProperty.get_next_update('score')
  lotd  = GlobalProperty.get_next_update(Level)
  eotw  = GlobalProperty.get_next_update(Episode)
  cotm  = GlobalProperty.get_next_update(Story)
  log("next updates: scores #{score}, level #{lotd}, episode #{eotw}, story #{cotm}")

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
  Twitch::update_twitch_streams
  streams = Twitch::active_streams

  event << "Currently active N related Twitch streams #{format_time}:"
  if streams.map{ |k, v| v.size }.sum == 0
    event << "None :shrug:"
  else
    str = ""
    streams.each{ |game, list|
      if list.size > 0
        str += "**#{game}**: #{list.size}\n"
        ss = list.take(20).map{ |stream| Twitch::format_stream(stream) }.join("\n")
        str += format_block(Twitch::table_header + "\n" + ss)
      end
    }
    event << str if !str.empty?
  end
end

# Add role to player (internal, for permission system, not related to Discord roles)
# Example: Add role "dmmc" for Donfuy
def add_role(event)
  assert_permissions(event)

  msg  = event.content
  user = parse_discord_user(msg)

  role = parse_term(msg)
  raise "You need to provide a role in quotes." if role.nil?

  Role.add(user, role)
  event << "Added role \"#{role}\" to #{user.username}."
end

# Add custom player / level alias.
# Example: Add level alias "sss" for sigma structure symphony
def add_alias(event)
  assert_permissions(event) # Only the botmaster can execute this

  msg = event.content
  aka = parse_term(msg)
  raise "You need to provide an alias in quotes." if aka.nil?

  msg.remove!(aka)
  type = !!msg[/\blevel\b/i] ? 'level' : (!!msg[/\bplayer\b/i] ? 'player' : nil)
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
  levels     = Userlevel.where_like('title', msg).to_a[0..limit - 1]
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
      zip.put_next_entry(sanitize_filename(u.author.name) + ' - ' + sanitize_filename(u.title) + '.png')
      zip.write(u.screenshot(palette))
      palettes.delete(palette)
    }
  }
  zip = zip_buffer.string
  response.delete
  send_file(event, zip, 'dmmc.zip', true)
end

# Clean database (remove cheated archives, duplicates, orphaned demos, etc)
# See Archive::sanitize for more details
def sanitize_archives(event)
  assert_permissions(event)
  counts = Archive::sanitize
  if counts.empty?
    event << "Nothing to sanitize."
    return
  end
  event << "Sanitized database:"
  counts.each{ |name, msg| event << "* #{msg}" }
end

def potato
  return if !RESPOND
  while true
    sleep(POTATO_RATE)
    next if $nv2_channel.nil? || $last_potato.nil?
    if Time.now.to_i - $last_potato.to_i >= POTATO_FREQ
      $nv2_channel.send_message(FRUITS[$potato])
      log(FRUITS[$potato].gsub(/:/, '').capitalize + 'ed nv2')
      $potato = ($potato + 1) % FRUITS.size
      $last_potato = Time.now.to_i
    end
  end
end

def mishnub(event)
  youmean = ["More like ", "You mean ", "Mish... oh, ", "Better known as ", "A.K.A. ", "Also known as "]
  amirite = [" amirite", " isn't that right", " huh", " am I right or what", " amirite or amirite"]
  mishu   = ["MishNUB,", "MishWho?,"]
  fellas  = [" fellas", " boys", " guys", " lads", " fellow ninjas", " friends", " ninjafarians"]
  laugh   = [" :joy:", " lmao", " hahah", " lul", " rofl", "  <:moleSmirk:336271943546306561>", " <:Kappa:237591190357278721>", " :laughing:", " rolfmao"]
  if rand < 0.05 && (event.channel.type == 1 || $last_mishu.nil? || !$last_mishu.nil? && Time.now.to_i - $last_mishu >= MISHU_COOLDOWN)
    event.send_message(youmean.sample + mishu.sample + amirite.sample + fellas.sample + laugh.sample) 
    $last_mishu = Time.now.to_i unless event.channel.type == 1
  end
end

def robot(event)
  start  = ["No! ", "Not at all. ", "Negative. ", "By no means. ", "Most certainly not. ", "Not true. ", "Nuh uh. "]
  middle = ["I can assure you he's not", "Eddy is not a robot", "Master is very much human", "Senpai is a ningen", "Mr. E is definitely human", "Owner is definitely a hooman", "Eddy is a living human being", "Eduardo es una persona"]
  ending = [".", "!", " >:(", " (ಠ益ಠ)", " (╯°□°)╯︵ ┻━┻"]
  event.send_message(start.sample + middle.sample + ending.sample)
end

def testa(event)
  assert_permissions(event)

#  maps = send_userlevel_browse(nil, socket: event.content)
#  Userlevel::dump_query(maps, 10, 0)
#  p = UserlevelAuthor.parse(parse_userlevel_author(event.content))
#  event << "Found: #{p.name}"
end

def send_reaction(event)
  msg = remove_command(event.content)
  flags = parse_flags(msg)
  react(flags[:c], flags[:m], flags[:r])
end

def send_unreaction(event)
  msg = remove_command(event.content)
  flags = parse_flags(msg)
  unreact(flags[:c], flags[:m], flags[:r])
end

def send_mappack_seed(event)
  Mappack.seed
  event << "Seeded new mappacks"
end

def send_mappack_patch(event)
  msg = remove_command(event.content)
  flags = parse_flags(msg)
  id = flags[:id]
  highscoreable = parse_level_or_episode(msg, mappack: true) if !id
  player = parse_player('for ' + flags[:p], nil, false, true, true) if !id
  score = parse_score(flags[:s])
  MappackScore.patch_score(id, highscoreable, player, score)
  if id.nil?
    event << "Patched #{player.name}'s score in #{highscoreable.name} to #{"%.3f" % score}."
  else
    s = MappackScore.find(id)
    event << "Patched #{s.player.name}'s score (#{s.id}) in #{s.highscoreable.name} to #{"%.3f" % score}."
  end
end

def send_mappack_info(event)
  msg = remove_command(event.content)
  flags = parse_flags(msg)
  mappack = parse_mappack(flags[:mappack], true)
  mappack.set_info(flags[:name], flags[:author], flags[:date])
  flags.delete(:mappack)
  flags = flags.map{ |k, v| "#{k} to `#{v}`" unless v.nil? }.compact.to_sentence
  event << "Set mappack `#{mappack.code}` #{flags}."
end

def send_gold_check(event)
  msg = remove_command(event.content)
  flags = parse_flags(msg)
  event << "List of potentially incorrect mappack scores:"
  event << format_block(MappackScore.gold_check.map{ |s|
    "#{s.id} by #{s.player.name} in #{s.highscoreable.name}"
  }.join("\n"))
end


def send_log_config(event)
  msg = remove_command(event.content)
  flags = parse_flags(msg)
  event << "Enabled logging modes: #{Log.modes.join(', ')}." if flags.empty?
  flags.each{ |f, v|
    str = ''
    case f
    when :l
      str = Log.level(v.to_sym) if !v.nil?
    when :f
      str = Log.fancy
    when :m
      str = Log.change_modes(v.split.map(&:to_sym)) if !v.nil?
    when :M
      str = Log.set_modes(v.split.map(&:to_sym)) if !v.nil?
    end
    event << str if !str.empty?
  }
end

def respond_special(event)
  assert_permissions(event)
  msg = event.content.strip
  cmd = msg[/^!(\w+)/i, 1]
  return if cmd.nil?
  send_reaction(event)           if cmd == 'react'
  send_unreaction(event)         if cmd == 'unreact'
  send_mappack_seed(event)       if cmd == 'mappack_seed'
  send_mappack_patch(event)      if cmd == 'mappack_patch'
  send_mappack_info(event)       if cmd == 'mappack_info'
  send_log_config(event)         if cmd == 'log'
rescue RuntimeError => e
  event << e
rescue => e
  lex(e, 'Failed to handle special message')
end

def respond(event)
  msg = event.content

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

  # mappack methods
  if !!msg[/mappack/i]
    respond_mappacks(event)
    return
  end

  # exclusively global methods, this conditional avoids the problem stated in the comment below
  if !msg[NAME_PATTERN, 2]
    send_rankings(event)    if msg =~ /rank/i && msg !~ /history/i && msg !~ /table/i
    send_history(event)     if msg =~ /history/i && msg !~ /rank/i
    send_diff(event)        if msg =~ /\bdiff\b/i
    send_community(event)   if msg =~ /community/i
    send_cleanliness(event) if msg =~ /cleanest/i || msg =~ /dirtiest/i
    send_ownages(event)     if msg =~ /ownage/i
    send_help(event)        if msg =~ /\bhelp\b/i || msg =~ /\bcommands\b/i
    send_help2(event)       if msg =~ /help2/i
    send_random(event)      if msg =~ /random/i
  end

  # on this methods, we will exclude a few problematic words that appear
  # in some level names which would accidentally trigger them
  hm = !msg[/\bhow many\b/i]
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
  send_total_score(event)    if msg =~ /total\b/i && msg !~ /history/i && msg !~ /rank/i && msg !~ /table/i && msg !~ /community/i
  send_list(event, false)    if msg =~ /how many/i && msg !~ /point/i unless !!msg[/\bmissing\b/i]
  send_list(event, false, false, true) if msg =~ /how cool/i 
  send_table(event)          if msg =~ /\btable\b/i
  send_comparison(event)     if msg =~ /\bcompare\b/i || msg =~ /\bcomparison\b/i
  send_stats(event)          if msg =~ /\bstat/i && msg !~ /generator/i && msg !~ /hooligan/i && msg !~ /space station/i
  send_screenshot(event)     if msg =~ /screenshot/i
  send_screenscores(event)   if msg =~ /screenscores/i || msg =~ /shotscores/i
  send_scoreshot(event)      if msg =~ /scoreshot/i || msg =~ /scorescreen/i
  send_suggestions(event)    if (msg =~ /\bworst\b/i && msg !~ /\bnightmare\b/i) || msg =~ /\bimprovable\b/i
  send_list(event)           if msg =~ /\blist\b/i unless msg =~ /of inappropriate words/i || !!msg[/\btally\b/i] || !!msg[/\bmissing\b/i]
  send_list(event, hm, true) if msg =~ /missing/i
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
  send_tally(event)          if msg =~ /\btally\b/i
  send_demo_download(event)  if (msg =~ /\breplay\b/i || msg =~ /\bdemo\b/i) && msg =~ /\bdownload\b/i
  send_trace(event)          if msg =~ /\btrace\b/i
  update_ntrace(event)       if msg =~ /\bupdate\s*ntrace\b/i
  faceswap(event)            if msg =~ /faceswap/i
  testa(event) if msg =~ /testa/i

rescue RuntimeError => e
  # Exceptions raised in here are user error, indicating that we couldn't
  # figure out what they were asking for, so send the error message out
  # to the channel
  event << e
end
