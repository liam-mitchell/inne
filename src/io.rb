require 'active_support/core_ext/integer/inflections' # ordinalize
require_relative 'constants.rb'

# Fetch message from an event. Depending on the event that was triggered, this is
# accessed in a different way. We use the "initial" boolean to determine whether
# the post is going to be created (in which case the event that triggered it is
# either a MentionEvent or a PrivateMessageEvent) or edited (in which case the
# event that triggered it must have been either a ButtonEvent or a SelectMenuEvent,
# or any other future interaction event).
def fetch_message(event, initial)
  if initial # MentionEvent / PrivateMessageEvent
    event.content
  else # ButtonEvent / SelectMenuEvent
    msg = event.message.content
    msg.split("```").first # Only header of message
  end
end

def compute_pages(msg, count = 1, page = 1)
  pages  = [(count.to_f / PAGE_SIZE).ceil, 1].max
  page   = page > pages ? pages : (page < 1 ? 1 : page)
  offset = (page - 1) * PAGE_SIZE
  { page: page, pages: pages, offset: offset }
end

def parse_mode(msg)
  !!msg[/race/i] ? 'race' : (!!msg[/coop/i] ? 'coop' : (!!msg[/solo/i] ? 'solo' : 'all'))
end

def parse_type(msg)
  ((msg[/level/i] || msg[/lotd/i]) ? Level : ((msg[/episode/i] || msg[/eotw/i]) ? Episode : ((msg[/\bstory\b/i] || msg[/\bcolumn/i] || msg[/hard\s*core/i] || msg[/\bhc\b/i] || msg[/cotm/i]) ? Story : nil)))
end

def parse_alias_type(msg, type = nil)
  ['level', 'player'].include?(type) ? type : (!!msg[/player/i] ? 'player' : 'level')
end

def normalize_name(name)
  name.split('-').map { |s| s[/\A[0-9]\Z/].nil? ? s : "0#{s}" }.join('-').upcase
end

def redash_name(matches)
  !!matches ? matches.captures.compact.join('-') : nil
end

def normalize_tab(tab)
  format_tab(parse_tabs(tab)[0])
end

def formalize_tab(tab)
  parse_tabs(tab)[0].to_s
end

# Auxiliary function for the following ones
def parse_player_explicit(name, playerClass = Player)
  player = playerClass.where.not(metanet_id: nil).find_by(name: name) rescue nil
  player = Player.joins('INNER JOIN player_aliases ON players.id = player_aliases.player_id')
                 .where(["player_aliases.alias = ?", name])
                 .take rescue nil if player.nil?
  raise "#{name} doesn't have any high scores! Either you misspelled the name / alias, or they're exceptionally bad..." if player.nil?
  player
end

# explicit: players will only be parsed if they appear explicitly, without inferring from their user, otherwise nil
# enforce: a player MUST be supplied explicitly, otherwise exception
# implicit: the player will be inferred from their user, without even parsing the comment
def parse_player(msg, username, userlevel = false, explicit = false, enforce = false, implicit = false)
  p = msg[/(for|of) (.*)[\.\?]?/i, 2]
  playerClass = userlevel ? UserlevelPlayer : Player

  # We make sure to only return players with metanet_ids, ie., with highscores.
  if implicit
    player = playerClass.where.not(metanet_id: nil).find_by(name: username)
    return player if !player.nil?
    user = User.find_by(username: username)
    raise "I couldn't find a player with your username! Have you identified yourself (with '@outte++ my name is <N++ display name>')?" if user.nil? || user.player.nil?
    parse_player_explicit(user.player.name, playerClass)
  else
    if p.nil?
      if explicit
        if enforce
          raise "You need to specify a player for this function."
        else
          nil
        end
      else
        player = playerClass.where.not(metanet_id: nil).find_by(name: username) rescue nil
        return player if !player.nil?
        user = User.find_by(username: username)
        raise "I couldn't find a player with your username! Have you identified yourself (with '@outte++ my name is <N++ display name>')?" if user.nil? || user.player.nil?
        parse_player_explicit(user.player.name, playerClass)
      end
    else
      parse_player_explicit(p, playerClass)
    end
  end
end

# Parse a pair of players. The user may provide 0, 1 or 2 names in different
# formats, so we act accordingly and reuse the previous method.
def parse_players(msg, username, userlevel = false)
  playerClass = userlevel ? UserlevelPlayer : Player
  p = msg.scan(/#{parse_term}/i).map(&:second)
  case p.size
  when 0
    p1 = parse_player(msg, username, userlevel, true, true, false)
    p2 = parse_player(msg, username, userlevel, false, false, true)
  when 1
    p1 = parse_player_explicit(p[0], playerClass)
    p2 = parse_player(msg, username, userlevel, false, false, true)
  when 2
    p1 = parse_player_explicit(p[0], playerClass)
    p2 = parse_player_explicit(p[1], playerClass)
  else
    raise "Too many players! Please enter either 1 or 2."
  end
  [p1, p2]
end

def parse_many_players(msg, userlevel = false)
  playerClass = userlevel ? UserlevelPlayer : Player
  msg = msg[/without (.*)/i, 1] || ""  
  players = msg.split(/,|\band\b|\bor\b/i).flatten.map(&:strip).reject(&:empty?)
  #pl = msg.scan(/#{parse_term}/i).map(&:second)
  players.map!{ |name|
    p = playerClass.where.not(metanet_id: nil).find_by(name: name)
    p.nil? ? name : p
  }
  errors = players.select{ |p| p.is_a?(String) }
  raise "#{format_sentence(errors)} #{errors.size == 1 ? "doesn't" : "don't"} have any high scores! Either you misspelled the name, or they're exceptionally bad... " if errors.size > 0
  players
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
  level     = msg[LEVEL_PATTERN]
  level_d   = msg.match(LEVEL_PATTERN_D) # dashless
  episode   = msg[EPISODE_PATTERN]
  episode_d = msg.match(EPISODE_PATTERN_D)
  story     = msg.match(STORY_PATTERN) # no need for dashed (no ambiguity)
  name      = msg[NAME_PATTERN, 2]
  ret       = nil
  str       = ""

  # 1) First we check dashed versions for levels and episodes
  # 2) Then dashless for levels and episodes (together)
  #     (Thus SU-A-10 will be parsed as the episode, not as the level SU-A-1-0
  #      missing some dashes, and SUA15 will be parsed as the episode SU-A-15,
  #      even though it also fits the dashless level SU-A-1-5, because no such
  #      level exists).
  # 3) Then parse columns (no ambiguity as they don't have row letter).
  # 4) Finally parse other specific strings (lotd, eotw, cotm, level names).
  if level
    str = normalize_name(level)
    ret = Level.find_by(name: str)
  elsif episode
    str = normalize_name(episode)
    ret = Episode.find_by(name: str)
  elsif level_d || episode_d
    if level_d
      str = normalize_name(redash_name(level_d))
      ret = Level.find_by(name: str)
    end
    if episode_d && !ret
      str = normalize_name(redash_name(episode_d))
      ret = Episode.find_by(name: str)
    end
  elsif story
    str = normalize_name(redash_name(story))
    ret = Story.find_by(name: str)
  elsif !msg[/(level of the day|lotd)/i].nil?
    ret = get_current(Level)
  elsif !msg[/(episode of the week|eotw)/i].nil?
    ret = get_current(Episode)
  elsif !msg[/(column of the month|cotm)/i].nil?
    ret = get_current(Story)
  elsif name
    str = name
    ret = Level.find_by("UPPER(longname) LIKE ?", name.upcase) rescue nil
    ret = Level.joins("INNER JOIN level_aliases ON levels.id = level_aliases.level_id")
               .find_by("UPPER(level_aliases.alias) = ?", name.upcase) rescue nil if ret.nil?
  else
    msg = "I couldn't figure out which level, episode or column you wanted scores for! You need to send either a level, " +
          "an episode or a column ID that looks like SI-A-00-00, SI-A-00 or SI-00; or a level name, using 'for <name>.'"
    raise msg
  end

  raise "I couldn't find any level, episode or story by the name `#{str}` :(" if ret.nil?
  ret
end

def parse_rank(msg)
  rank = msg[/top\s*([0-9][0-9]?)/i, 1]
  rank ? rank.to_i.clamp(1, 20) : nil
end

def parse_bottom_rank(msg)
  rank = msg[/bottom\s*([0-9][0-9]?)/i, 1]
  rank ? (20 - rank.to_i).clamp(0, 19) : nil
end

def parse_ranks(msg)
  ranks = msg.scan(/\s+([0-9][0-9]?)/).map{ |r| r[0].to_i }.reject{ |r| r < 0 || r > 19 }
  ranks.empty? ? [0] : ranks
end

# We parse a complex variery of ranges here, from individual ranks, to tops,
# bottoms, intermediate ranges, etc.
def parse_range(msg)
  rank   = parse_rank(msg) || 20
  bott   = parse_bottom_rank(msg) || 0
  ind    = nil
  dflt   = parse_rank(msg).nil? && parse_bottom_rank(msg).nil?
  valid  = true
  20.times.each{ |r| ind = r if !!(msg =~ /\b#{r.ordinalize}\b/i) }

  # If no range is provided, default to 0th count
  if dflt
    bott = 0
    rank = 1
  end

  # If an individual rank is provided, the range has width 1
  if !ind.nil?
    bott = ind
    rank = ind + 1
  end

  # The range must make sense   
  if bott >= rank
    valid = false
  end

  [bott, rank, valid]
end

def parse_tabs(msg)
  ret = []

  ret << :SI if msg =~ /\b(intro|SI)\b/i
  ret << :S if msg =~ /(\b|\A|\s)(N++|S|solo)(\b|\Z|\s)/i
  ret << :SU if msg =~ /\b(SU|UE|ultimate)\b/i
  ret << :SL if msg =~ /\b(legacy|SL)\b/i
  ret << :SS if msg =~ /(\A|\s)(secret|\?)(\Z|\s)/i
  ret << :SS2 if msg =~ /(\A|\s)(ultimate secret|!)(\Z|\s)/i

  ret
end

# This is used mainly for page navigation. We determine the current page,
# and we also determine whether we need to add an offset to it (to navigate)
# or reset it (when a different component, e.g. a select menu) was activated.
def parse_page(msg, offset = 0, reset = false, components = nil)
  page = nil
  components.to_a.each{ |row|
    row.each{ |component|
      page = component.label.to_s[/\d+/i].to_i if component.custom_id.to_s == 'button:nav:page'
    }
  }
  reset ? 1 : (page || msg[/page:?[\s\*]*(\d+)/i, 1] || 1).to_i + offset.to_i
rescue => e
  err(e)
  1
end

# Regex to determine the field to order by in userlevel searches
# Order may be inverted by specifying a "-" before, or a "desc" after, or both
# It then modifies the original message to remove the order query part
def parse_order(msg, order = nil)
  regex  = /(order|sort)(ed)?\s*by\s*((\w|\+|-)*)\s*(asc|desc)?/i
  order  = order || msg[regex, 3] || ""
  desc   = msg[regex, 5] == "desc"
  invert = (order.strip[/\A-*/i].length % 2 == 1) ^ desc
  order.delete!("-")
  msg.remove!(regex)
  { msg: msg, order: order, invert: invert }
end

# The following function is supposed to modify the message!
#
# Supports querying for both titles and author names. If both are present, at
# least one must go in quotes, to distinguish between them. The one without
# quotes must go at the end, so that everything after the particle is taken to
# be the title/author name.
#
# The first thing we do is parse the terms in quotes. Then we remove them from
# the message and parse the potential non-quoted counterparts. Then we remove
# these as well if found, and finish parsing the rest of the message, which
# is only keywords and hence poses no ambiguity. In between these two we parse
# the order, since that also begins with "by".
def parse_title_and_author(msg)
  strs = [
    [ # Primary queries
      { str: /\bfor\s*#{parse_term}/i, term: 2 }, # Title
      { str: /\bby\s*#{parse_term}/i,  term: 2 }  # Author
    ],
    [ # Secondary queries
      { str: /\bfor (.*)/i,            term: 1 }, # Title
      { str: /\bby (.*)/i,             term: 1 }  # Author
    ]
  ]
  queries = [""] * strs.first.size
  strs.each_with_index{ |q, j|
    q.each_with_index{ |sq, i|
      if !msg[sq[:str]].nil?
        if queries[i].empty?
          queries[i] = msg[sq[:str], sq[:term]]
        end
        msg.remove!(sq[:str])
      end
    }
  }
  { msg: msg, search: queries[0].strip, author: queries[1].strip }
end

def clean_userlevel_message(msg)
  msg.sub(/(for)?\s*\w*userlevel\w*/i, '')
end

def parse_userlevel(msg)
  # --- PARSE message elements

  # Parse author and remove from message, if exists
  author_regex = /by\s*#{parse_term}/i
  author = msg[author_regex, 2] || ""
  msg.remove!(author_regex)

  # Parse title, first in quotes, and if that doesn't exist, then everything remaining
  title = msg[/#{parse_term}/i, 2]
  if title.nil?
    title = msg.strip[/(for|of)?\s*(.*)/i, 2]
    # If the "title" is just numbers (and not quoted), then it's actually the ID
    id    = title == title[/\d+/i] ? title.to_i : -1
  else
    id = -1
  end

  # --- FETCH userlevel(s)
  query = nil
  err   = ""
  count = 0
  if id != -1
    query = Userlevel.where(id: id)
    err = "No userlevel with ID `#{id}` found."
  elsif !title.empty?
    query = Userlevel.where(Userlevel.sanitize("title LIKE ?", "%" + title[0..63] + "%"))
    query = query.where(Userlevel.sanitize("author LIKE ?", "%" + author[0..63] + "%")) if !author.empty?
    err = "No userlevel with title `#{title}`#{" by author `#{author}`" if !author.empty?} found."
  else
    return {
      query: nil,
      msg:   "You need to provide a map's title or ID.",
      count: 0
    }
  end

  # --- Prepare return depending on map count
  ret   = ""
  count = query.count
  case count
  when 0
    ret = err
  when 1
    query = query.first
  else
    ret = "Multiple matching maps found. Please refine terms or use the userlevel ID:"
  end
  { query: query, msg: ret, count: count, title: title, author: author }
end

# The palette may or may not be quoted, but it MUST go at the end of the command
# if it's not quoted
def parse_palette(msg)
  err = ""
  regex1 = /\b(using|with|in)?(the)?\s*pall?ett?e\s*#{parse_term}/i
  regex2 = /\b(using|with|in)?\s*pall?ett?e\s*(.*)/i
  pal1 = msg[regex1, 4]
  pal2 = msg[regex2, 2]
  pal = nil
  if !pal1.nil?
    if Userlevel::THEMES.include?(pal1)
      pal = pal1
    else
      err = "The palette `" + pal1 + "` doesn't exit. Using default: `" + Userlevel::DEFAULT_PALETTE + "`."
    end
    msg.remove!(regex1)
  elsif !pal2.nil?
    if Userlevel::THEMES.include?(pal2)
      pal = pal2
    else
      err = "The palette `" + pal2 + "` doesn't exit. Using default: `" + Userlevel::DEFAULT_PALETTE + "`."
    end
    msg.remove!(regex2)
  end
  pal = Userlevel::DEFAULT_PALETTE if pal.nil?
  err += "\n" if !err.empty?
  { msg: msg, palette: pal, error: err }
end

# We build the regex: /("|“|”)([^"“”]*)("|“|”)/i
# which parses a term in between different types of quotes
def parse_term(opt = false)
  quotes = ["\"", "“", "”"]
  "(#{quotes.join('|')})([^#{quotes.join}]*)(#{quotes.join('|')})"
end

def parse_userlevel_author(msg)
  msg[/((by)|(author))\s*#{parse_term}/i, 5] || ""
end

def parse_global(msg)
  !!msg[/global/i]
end

def parse_full(msg)
  !!msg[/full/i]
end

def parse_newest(msg)
  !!msg[/newest/i]
end

def format_rank(rank)
  rank == 1 ? "0th" : "top #{rank}"
end

def format_bottom_rank(rank)
  "bottom #{20 - rank}"
end

def format_range(bott, rank)
  if bott == rank - 1
    header = "#{bott.ordinalize}"
  elsif bott == 0
    header = format_rank(rank)
  elsif rank == 20
    header = format_bottom_rank(bott)
  else
    header = "#{bott.ordinalize}-#{(rank - 1).ordinalize}"
  end
end

def format_type(type)
  (type || 'Overall').to_s
end

def format_ties(ties)
  ties ? " with ties" : ""
end

def format_tied(tied)
  tied ? "tied " : ""
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

def format_global(full)
  full ? "global " : "newest "
end

def format_full(full)
  full ? "full " : ""
end

def format_max(max)
  !max.nil? ? " [MAX. #{(max.is_a?(Integer) ? "%d" : "%.3f") % max}]" : ""
end

def format_author(name)
  !name.empty? ? "on maps by #{name}" : ""
end

def format_entry(arr)
  arr[0].to_s.rjust(2, "0") + ": " + arr[2].ljust(10) + " - " + ("%.3f" % [arr[3]]).rjust(8)
end

def format_pair(arr)
  "[" + format_entry(arr[0]) + "] vs. [" + format_entry(arr[1]) + "]"
end

def format_block(str)
  "```\n#{str}```"
end

def format_sentence(e)
  return e[0].to_s if e.size == 1
  e[-2] = e[-2].to_s + " and #{e[-1].to_s}"
  e[0..-2].map(&:to_s).join(", ")
end

def format_list_score(s)
  "#{HighScore.format_rank(s.rank)}: #{s.highscoreable.name.ljust(10, " ")} - #{"%7.3f" % [s.score]}"
end

def send_file(event, data, name = "result.txt", binary = false)
  tmpfile = File.join(Dir.tmpdir, name)
  File::open(tmpfile, binary ? "wb" : "w", crlf_newline: !binary) do |f|
    f.write(data)
  end
  event.attach_file(File::open(tmpfile))
end
