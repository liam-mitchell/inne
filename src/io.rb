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

# Given an amount and a page number, will make sure that it is a valid
# page number (given the page size), or clamp it otherwise, as well as
# find the offset index where the page begins.
def compute_pages(count = 1, page = 1, pagesize = PAGE_SIZE)
  pages  = [(count.to_f / pagesize).ceil, 1].max
  page   = page > pages ? pages : (page < 1 ? 1 : page)
  offset = (page - 1) * pagesize
  { page: page, pages: pages, offset: offset }
end

def parse_mode(msg)
  !!msg[/race/i] ? 'race' : (!!msg[/coop/i] ? 'coop' : (!!msg[/solo/i] ? 'solo' : 'all'))
end

# Optionally allow to parse multiple types, for retrocompat
def parse_type(msg, type = nil, multiple = false, initial = false)
  type = type.capitalize.constantize unless type.nil?
  return type if !multiple && ['level', 'episode', 'story'].include?(type.to_s.downcase)
  ret = []
  multiple ? ret << Level :   (return Level)   if !!msg[/level/i] || !!msg[/lotd/i]
  multiple ? ret << Episode : (return Episode) if !!msg[/episode/i] || !!msg[/eotw/i]
  multiple ? ret << Story :   (return Story)   if !!msg[/\bstory\b/i] || !!msg[/\bcolumn/i] || !!msg[/hard\s*core/i] || !!msg[/\bhc\b/i] || !!msg[/cotm/i]
  if multiple
    ret.push(*DEFAULT_TYPES.map(&:constantize)) if !!msg[/\boverall\b/i] || initial && ret.empty?
    ret.include?(type) ? ret.delete(type) : ret.push(type) if !type.nil?
    ret.uniq!
  end
  return multiple ? ret : nil
end

# Normalize how highscoreable types are handled.
# A good example:
#   [Level, Episode]
# Bad examples:
#   nil   (transforms to [Level, Episode])
#   Level (transforms to [Level])
# 'single' means we return a singly type instead
def fix_type(type, single = false)
  if single
    ensure_type(type)
  else
    type.nil? ? DEFAULT_TYPES : (!type.is_a?(Array) ? [type] : type)
  end
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

# Transform tab into [SI, S, SU, SL, ?, !] format
def normalize_tab(tab)
  format_tab(parse_tabs(tab)[0])
end

# Transform tab into [SI, S, SU, SL, SS, SS2] format
def formalize_tab(tab)
  parse_tabs(tab)[0].to_s
end

# The following are 2 auxiliary functions for the next ones
#   Parse a single player when a name has been provided
def parse_player_explicit(name, playerClass = Player)
  player = playerClass.where.not(metanet_id: nil).find_by(name: name) rescue nil
  player = Player.joins('INNER JOIN player_aliases ON players.id = player_aliases.player_id')
                 .where(["player_aliases.alias = ?", name])
                 .take rescue nil if player.nil?
  raise "#{name} doesn't have any high scores! Either you misspelled the name / alias, or they're exceptionally bad..." if player.nil?
  player
end

#   Parse a single player when a username has been provided
def parse_player_implicit(username, playerClass = Player)
  # Check if player with username exists
  player = playerClass.where.not(metanet_id: nil).find_by(name: username) rescue nil
  return player if !player.nil?
  # Check if user identified with another name
  user = User.find_by(username: username) rescue nil
  raise "I couldn't find a player with your username! Have you identified yourself (with '@outte++ my name is <N++ display name>')?" if user.nil? || user.player.nil?
  parse_player_explicit(user.player.name, playerClass)
end

# explicit: players will only be parsed if they appear explicitly, without inferring from their user, otherwise nil
# enforce: a player MUST be supplied explicitly, otherwise exception
# implicit: the player will be inferred from their user, without even parsing the comment
def parse_player(msg, username, userlevel = false, explicit = false, enforce = false, implicit = false)
  p = msg[/(for|of) (.*)[\.\?]?/i, 2]
  playerClass = userlevel ? UserlevelPlayer : Player

  # We make sure to only return players with metanet_ids, ie., with highscores.
  if implicit
    parse_player_implicit(username, playerClass)
  else
    if p.nil?
      if explicit
        if enforce
          raise "You need to specify a player for this function."
        else
          nil
        end
      else
        parse_player_implicit(username, playerClass)
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
  players.map{ |name| parse_player_explicit(name) }
end

# The username can include the tag after a hash
def parse_discord_user(msg)
  user = msg[NAME_PATTERN, 2]
  raise "You need to provide a user." if user.nil?

  parts = user.split('#')
  users = User.search(parts[0], !parts[1].nil? ? parts[1] : nil)
  case users.size
  when 0
    raise "No user named #{user} found in the server."
  when 1
    return users.first
  else
    list = users.map{ |u| u.username + '#' + u.tag }.join("\n")
    raise "Multiple users named #{parts[0]} found, please include the numerical tag as well:\n#{format_block(list)}"
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

# If 'partial' is activated, then after testing for all possible ways to parse
# the level (e.g. level ID, level name, etc) we will also perform other kinds of
# searches (e.g. partial, word distance, etc) using a different function.
# We use a parameter instead of making this a default because it might return
# multiple results in an array, rather than a single Level instance, and so this
# would break all the many prior uses of this function.
# If 'array' is true, then even if there's a single result, it will be returned
# as an array.
def parse_level_or_episode(msg, partial: false, array: false)
  level     = msg[LEVEL_PATTERN]
  level_d   = msg.match(LEVEL_PATTERN_D) # dashless
  episode   = msg[EPISODE_PATTERN]
  episode_d = msg.match(EPISODE_PATTERN_D)
  story     = msg.match(STORY_PATTERN) # no need for dashed (no ambiguity)
  name      = msg.split("\n")[0][NAME_PATTERN, 2]
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
  # For the last step, a list with multiple matches might be returned instead.
  # It will be returned in the format:
  # [String, Array<Level>]
  # Where the string is a message, because the origin of the list might differ
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
    # Parse exact name
    ret = ["Multiple matches found for #{name}", Level.where("UPPER(longname) LIKE ?", name.upcase).to_a]
    ret = ret[1][0] if !partial || ret[1].size == 1
    # Parse level alias
    if ret.nil? || ret.is_a?(Array) && ret[1].empty?
      ret = Level.joins("INNER JOIN level_aliases ON levels.id = level_aliases.level_id")
                 .find_by("UPPER(level_aliases.alias) = ?", name.upcase) 
    end
    # If specified, perform extra searches
    if ret.nil? || ret.is_a?(Array) && ret[1].empty?
      ret = search_level(msg) 
      ret = ret[1][0] if !partial || ret[1].size == 1
    end
  else
    raise "Couldn't find the level, episode or story you were looking for :("
  end

  raise "I couldn't find any level, episode or story by the name `#{str}` :(" if ret.nil? || ret.is_a?(Array) && ret[1].empty?
  ret = ["Single match found for #{name}", [ret]] if !ret.is_a?(Array) && array
  ret
end

# Completes previous function by adding extra level searching functionality
# 1) First, look for partial matches (i.e. using wildcards at start and end)
# 2) Then, minimize Damerau-Levenshtein string distance
def search_level(msg)
  name = msg[NAME_PATTERN, 2]
  if name
    # Partial matches
    ret = [
      "Multiple partial matches found for #{name}",
      Level.where("UPPER(longname) LIKE ?", '%' + name.upcase + '%').to_a
    ]
    # If no result, minimize string distance
    if ret[1].empty?
        list = Level.all.pluck(:name, :longname)
        matches = string_distance_list_mixed(name, list)
        ret = [
          "No matches found for `#{name}`. Did you mean...",
          matches.map{ |m| Level.find_by(name: m[0]) }
        ]
    end
  else
    ret = ["", []]
  end
  ret
rescue
  ["", []]
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

def parse_nav(msg)
  !!msg[/\bnav((igat)((e)|(ing)))?\b/i]
end

def parse_offline(msg)
  !!msg[/\boffline\b/i]
end

def parse_maxed(msg)
  !!msg[/\bmaxed\b/i]
end

def parse_maxable(msg)
  !!msg[/\bmaxable\b/i]
end

# We parse a complex variety of ranges here, from individual ranks, to tops,
# bottoms, intermediate ranges, etc.
# 'full' means that if no range has been explicitly provided, then we default
# to 0th-19th, otherwise we default to 0th-1st.
def parse_range(msg, full = false)
  # Parse "topX" and "bottomX"
  rank = parse_rank(msg) || 20
  bott = parse_bottom_rank(msg) || 0
  # Parse up to 2 individual ranks (e.g. 2nd, 7th...)
  inds = msg.scan(/\b[0-9][0-9]?(?:st|nd|rd|th)\b/i)
            .map{ |r| r.to_i.clamp(0, 20) }
            .uniq
            .sort
            .take(2)
  # If there's only 1 individual rank, the interval has width 1
  inds.push(inds.first) if inds.size == 1
  # Figure out if we need to default
  dflt = parse_rank(msg).nil? && parse_bottom_rank(msg).nil?

  # If no range is provided, default to 0th count
  if dflt
    if full
      bott = 0
      rank = 20
    else
      bott = 0
      rank = 1
    end
  end

  # If an individual rank is provided, the range has width 1
  if !inds.empty?
    bott = inds[0].clamp(0, 19)
    rank = (inds[1] + 1).clamp(1, 20)
  end

  [bott, rank, bott < rank]
end

# Parse a message for tabs
# If 'tab' is passed, we're in a select menu, and we
# include either one tab or none (all)
def parse_tabs(msg, tab = nil)
  if !tab.nil?
    if ['si', 's', 'su', 'sl', 'ss', 'ss2'].include?(tab)
      [tab.upcase.to_sym]
    else
      []
    end
  else
    ret = []
    ret << :SI  if msg =~ /\b(intro|SI)\b/i
    ret << :S   if msg =~ /(\b|\A|\s)(N++|S|solo)(\b|\Z|\s)/i
    ret << :SU  if msg =~ /\b(SU|UE|ultimate)\b/i
    ret << :SL  if msg =~ /\b(legacy|SL)\b/i
    ret << :SS  if msg =~ /(\A|\s)(secret|\?)(\Z|\s)/i
    ret << :SS2 if msg =~ /(\A|\s)(ultimate secret|!)(\Z|\s)/i
    ret.size == 6 ? [] : ret
  end
end

# Ranking type
def parse_rtype(msg)
  if !!msg[/average/i] && !!msg[/point/i]
    'average_point'
  elsif !!msg[/average/i] && !!msg[/lead/i]
    'average_top1_lead'
  elsif !!msg[/average/i]
    'average_rank'
  elsif !!msg[/point/i]
    'point'
  elsif !!msg[/score/i]
    'score'
  elsif parse_singular(msg) == 1
    'singular_top1'
  elsif parse_singular(msg) == -1
    'plural_top1'
  elsif !!msg[/tied/i]
    'tied_top1'
  elsif parse_maxed(msg)
    'maxed'
  elsif parse_maxable(msg)
    'maxable'
  elsif parse_cool(msg)
    'cool'
  elsif parse_star(msg)
    'star'
  else
    'top'
  end
end

# Complete rtype with additional rank info
def fix_rtype(rtype, rank)
  rtype += rank.to_s if rtype == 'top'
  rtype
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

def parse_ties(msg, rtype = nil)
  !rtype.nil? && rtype[-2..-1] == '_t' || !!msg[/\bties\b/i]
end

def parse_tied(msg)
  !!msg[/\btied\b/i]
end

def parse_singular(msg)
  if !!msg[/\bsingular\b/i]
    1
  elsif !!msg[/\bplural\b/i]
    -1
  else
    0
  end
end

# 'strict' means the emoji must be separated from text
# intended to ignore users with it in the name
def parse_cool(msg, strict = false)
  !!msg[/\bcool(s|(ness))?\b/i] || !!msg[/\bckc'?s?\b/i] || !!msg[/#{strict ? "(\A|\W)" : ""}😎'?s?#{strict ? "(\z|\W)" : ""}/i]
end

# see parse_cool for 'strict'
# if 'name' then we accept 'star' for parsing stars as well
def parse_star(msg, strict = false, name = false)
  !!msg[/#{strict ? "(\A|\W)" : ""}\*#{strict ? "(\z|\W)" : ""}/i] || !!msg[/\bstar\b/i]
end

def format_rank(rank)
  rank.to_i == 1 ? '0th' : "top #{rank}"
end

# Formats a ranking type. These can include the range in some default cases
# (e.g. Top10 Rankings), unless the 'range' parameter is false.
# 'range' Includes the range (e.g. Top10) or not
# 'rank'  Overrule whatever the rank in the rtype is
# 'ties'  Adds "w/ ties" or something
# 'basic' Doesn't print words which are now parameters (e.g. cool)
def format_rtype(rtype, range: true, rank: nil, ties: false, basic: false)
  if rtype[0..2] == 'top'
    if range
      rtype = format_rank(rank || rtype[/\d+/i] || 1)
    else
      rtype = rtype.split('_')[1..-1].join('_') if !range
    end
  end
  rtype = rtype.gsub('top1', '0th').gsub('star', '*').tr('_', ' ')
  rtype.remove!('cool', '*', 'maxed', 'maxed') if basic
  "#{rtype} rankings #{format_ties(ties)}".squish
end

def format_bottom_rank(rank)
  "bottom #{20 - rank}"
end

# 'empty' means we print nothing
# This is used for when the calling function actually has other parameters
# that make is unnecessary to actually print the range 
def format_range(bott, rank, empty = false)
  return '' if empty
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

def format_singular(sing)
  case sing
  when 1
    'singular'
  when -1
    'plural'
  else
    ''
  end
end

def format_cool(cool)
  cool ? 'cool' : ''
end

def format_star(star)
  star ? '*' : ''
end

def format_maxed(maxed)
  maxed ? 'maxed' : ''
end

def format_maxable(maxable)
  maxable ? 'maxable' : ''
end

# Support for any single and multiple types
# 'empty' allows for no type, otherwise it's 'overall',
# which defaults to levels and episodes
def format_type(type, empty = false)
  return 'Overall' if type.nil?
  return type.to_s if !type.is_a?(Array) 
  case type.size
  when 0
    empty ? '' : 'Overall'
  when 1
    type.first.to_s
  when 2
    if type.include?(Level) && type.include?(Episode)
      'Overall'
    else
      type.map{ |t| t.to_s.downcase }.join(" and ").capitalize
    end
  when 3
    'Overall (w/ HC)'
  end
end

def format_ties(ties)
  ties ? '(w/ ties)' : ''
end

def format_tied(tied)
  tied ? 'tied' : ''
end

def format_tab(tab)
  (tab == :SS2 ? '!' : (tab == :SS ? '?' : tab.to_s))
end

def format_tabs(tabs)
  tabs.map { |t| format_tab(t) }.to_sentence
end   

def format_time
  Time.now.strftime("on %A %B %-d at %H:%M:%S (%z)")
end

def format_global(full)
  full ? 'global' : 'newest'
end

def format_full(full)
  full ? 'full' : ''
end

def format_max(max)
  !max.nil? ? " [MAX. #{(max.is_a?(Integer) ? "%d" : "%.3f") % max}]" : ''
end

def format_author(name)
  !name.empty? ? "on maps by #{name}" : ''
end

def format_block(str)
  str = " " if str.empty?
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

def format_level_list(levels)
  pad = levels.map{ |l| l.name.length }.max + 1
  format_block(levels.map{ |s| s.name.ljust(pad, ' ') + s.longname }.join("\n"))
end

def format_level_matches(event, msg, page, initial, matches, func)
  exact = matches[0].split(' ')[0] == "Multiple"
  if exact  # Multiple partial matches
    page = parse_page(msg, page, false, event.message.components)
    pag  = compute_pages(matches[1].size, page)
    list = matches[1][pag[:offset]...pag[:offset] + PAGE_SIZE]
  else # No partial matches, but suggestions based on string distance
    list = matches[1][0..PAGE_SIZE - 1]
  end
  str  = "#{func.capitalize} - #{matches[0]}\n#{format_level_list(list)}"
  if exact && matches[1].size > PAGE_SIZE
    view = Discordrb::Webhooks::View.new
    interaction_add_button_navigation(view, pag[:page], pag[:pages])
    send_message_with_interactions(event, str, view, !initial)
  else
    event << str
  end
end

def send_file(event, data, name = "result.txt", binary = false)
  tmpfile = File.join(Dir.tmpdir, name)
  File::open(tmpfile, binary ? "wb" : "w", crlf_newline: !binary) do |f|
    f.write(data)
  end
  event.attach_file(File::open(tmpfile))
end
