require 'active_support/core_ext/integer/inflections' # ordinalize
require_relative 'constants.rb'
require_relative 'utils.rb'

# Fetch message from an event. Depending on the event that was triggered, this is
# accessed in a different way. We use the "initial" boolean to determine whether
# the post is going to be created (in which case the event that triggered it is
# either a MentionEvent or a PrivateMessageEvent) or edited (in which case the
# event that triggered it must have been either a ButtonEvent or a SelectMenuEvent,
# or any other future interaction event).
# TODO: If initial is nil, we can deduce it from the event class. Implement this,
# perhaps even remove the initial part. MentionEvent and PrivateMessageEvent
# inherit from MessageEvent, and the other 2 inherit from ComponentEvent, use these.
# Obviously, fix all usages of fetch_message in other files.
def fetch_message(event, initial = nil)
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

# Parse game mode from string. If explicit is set, one of the 3 modes must be
# set (defaulting to 'solo'), otherwise, it defaults to 'all', or nil if
# 'null' is true
def parse_mode(msg, explicit = false, null = false)
  !!msg[/\brace\b/i] ? 'race' : (!!msg[/\bcoop\b/i] ? 'coop' : (explicit ? 'solo' : (!!msg[/\bsolo\b/i] ? 'solo' : (null ? nil : 'all'))))
end

# Parses a string looking for a score in the usual N++ 3-decimal floating point format
def parse_score(str)
  score = str[/(\s|^)([1-9]\d*|0)(\.\d{1,3})?(\s|$)/]
  raise "Couldn't find / understand the score" if score.nil?
  raise "The score is incorrect" if !verify_score(score.to_f)
  score.to_f
end

# Optionally allow to parse multiple types
def parse_type(msg, type = nil, multiple = false, initial = false, default = nil)
  # Sanitize default type
  default = nil if !['level', 'episode', 'story'].include?(default.to_s.downcase)

  # First, parse the parameter we sent
  type = type.to_s.capitalize.constantize unless type.nil?
  return type if !multiple && ['level', 'episode', 'story'].include?(type.to_s.downcase)

  # If it's not correct, then parse message
  ret = []
  multiple ? ret << Level   : (return Level)   if !!msg[/level/i] || !!msg[/lotd/i]
  multiple ? ret << Episode : (return Episode) if !!msg[/episode/i] || !!msg[/eotw/i]
  multiple ? ret << Story   : (return Story)   if !!msg[/\bstory\b/i] || !!msg[/\bstories\b/i] || !!msg[/\bcolumn/i] || !!msg[/hard\s*core/i] || !!msg[/\bhc\b/i] || !!msg[/cotm/i]

  if multiple
    # If still empty (and initial), push default types
    if initial && ret.empty?
      default.nil? ? ret.push(*DEFAULT_TYPES.map(&:constantize)) : ret.push(default.to_s.capitalize.constantize)
    end

    # If "overall" is matched, push default types too
    if !!msg[/\boverall\b/i]
      ret.push(*DEFAULT_TYPES.map(&:constantize))
    end

    # Also, toggle the type we sent (add or remove) (see rankings navigation)
    ret.include?(type) ? ret.delete(type) : ret.push(type) if !type.nil?
    ret.uniq!
  else
    # If not multiple, we return either the default we sent, or nil (type not found)
    ret = !default.nil? ? default.to_s.capitalize.constantize : nil
  end

  ret
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
    type.nil? ? DEFAULT_TYPES.map(&:constantize) : (!type.is_a?(Array) ? [type] : type)
  end
end

def parse_alias_type(msg, type = nil)
  ['level', 'player'].include?(type) ? type : (!!msg[/player/i] ? 'player' : 'level')
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
# third: allow for 3rd person specification "is xela" rather than "for xela"
def parse_player(msg, username, userlevel = false, explicit = false, enforce = false, implicit = false, third = false)
  msg = msg.gsub(/"/, '')
  p = msg[/(for|of#{third ? '|is' : ''}) (.*)[\.\?]?/i, 2]
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
  p = parse_term(msg, global: true)
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
  user = msg[NAME_PATTERN, 2].downcase
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
# If 'mappack' is true, then we allow to search in mappack highscoreables.
def parse_level_or_episode(msg, partial: false, array: false, mappack: false)
  level       = msg[LEVEL_PATTERN]
  level_d     = msg.match(LEVEL_PATTERN_D)
  level_m     = msg[LEVEL_PATTERN_M]
  level_m_d   = msg.match(LEVEL_PATTERN_M_D)
  episode     = msg[EPISODE_PATTERN]
  episode_d   = msg.match(EPISODE_PATTERN_D)
  episode_m   = msg[EPISODE_PATTERN_M]
  episode_m_d = msg.match(EPISODE_PATTERN_M_D)
  story       = msg.match(STORY_PATTERN) # no need for dashless (no ambiguity)
  story_m     = msg.match(STORY_PATTERN_M)
  name        = msg.split("\n")[0][NAME_PATTERN, 2]
  mappack     = mappack && (level_m || level_m_d || episode_m || episode_m_d || story_m)
  ret         = nil
  str         = ""

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

  if mappack # Parse mappack IDs first, if we allow it
    if level_m
      str = normalize_name(level_m)
      ret = MappackLevel.find_by(name: str)
    elsif episode_m
      str = normalize_name(episode_m)
      ret = MappackEpisode.find_by(name: str)
    elsif level_m_d || episode_m_d
      if level_m_d
        str = normalize_name(redash_name(level_m_d))
        ret = MappackLevel.find_by(name: str)
      end
      if episode_m_d && !ret
        str = normalize_name(redash_name(episode_m_d))
        ret = MappackEpisode.find_by(name: str)
      end
    elsif story_m
      str = normalize_name(redash_name(story_m))
      ret = MappackStory.find_by(name: str)
    end
  else # Parse normal IDs and names, if we found no mappack results
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
      ret = GlobalProperty.get_current(Level)
    elsif !msg[/(episode of the week|eotw)/i].nil?
      ret = GlobalProperty.get_current(Episode)
    elsif !msg[/(column of the month|cotm)/i].nil?
      ret = GlobalProperty.get_current(Story)
    elsif name
      str = name
      # Parse exact name
      ret = [
        "Multiple matches found for #{name}",
        Level.where_like('longname', name, partial: false).to_a
      ]
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
  end

  raise "I couldn't find any level, episode or story by the name `#{str}` :(" if ret.nil? || ret.is_a?(Array) && ret[1].empty?
  ret = ["Single match found for #{name}", [ret]] if !ret.is_a?(Array) && array
  ret
rescue RuntimeError
  raise
rescue => e
  lex(e, 'Failed to parse highscoreable')
  nil
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
      Level.where_like('longname', name).to_a
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

def parse_ranks(msg, clamp = 20)
  ranks = msg.scan(/\b\d{1,2}\b/)
             .map{ |r| r[0].to_i.clamp(0, clamp - 1) }
             .uniq
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

# Parse a mappack from a message, we try 4 methods:
# 1) The first word of the message, by mappack name
# 2) A quoted term, by name
# 3) At the using, using "for ...", by name
# 4) Anywhere, using the 3 letter mappack code
# The second parameter specifies the behaviour when the mappack is not found
def parse_mappack(msg, rais = false)
  mappack = Mappack.find_by(name: msg.strip[/\w+/i])
  return mappack if !mappack.nil?

  mappack = Mappack.find_by(name: parse_term(msg, quoted: [], final: ['for']))
  return mappack if !mappack.nil?

  mappack = Mappack.where(code: msg.scan(/\b[A-Z]{3}\b/i)).first
  return mappack if !mappack.nil?

  rais ? raise("Mappack not found") : nil
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
  elsif !!msg[/\bscore/i]
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

# Parse a quoted term from a string. Features:
# - Can handle quotes themselves, if they're escaped
# - An array of prefixes to match before the quoted term (can also be a single string)
# - Robust, never raises exceptions, always returns a string
# - Also supports a mode to match everything after the prefix, or even both
#   (in which case, the quoted match takes preference)
# 'quoted' contains the array of prefixes for quoted terms, can be empty
# 'final'  contains the array of prefixes for general matches, cannot be empty
# 'global' returns an array with all matches, rather than only the first
#          (only valid for quoted parses)
# 'remove' returns an array with the match, and the msg with the match removed
def parse_term(str, quoted: nil, final: nil, global: false, remove: false)
  return (remove ? ['', str] : '') if !str.is_a?(String)
  final = nil if global
  prefix = [
    regexize_words(quoted),
    regexize_words(final)
  ]
  regex = [
    /#{prefix[0]}\s*"((?:(?:\\.)|[^\\"])*)"/i,
    /#{prefix[1]}\s+(.*)/i
  ]
  str.gsub!(/["“”`´]/, '"')
  if global
    matches = str.scan(regex[0]).map(&:first)
    return (remove ? [matches, str.remove(regex[0])] : matches)
  end
  match = [
    str[regex[0], 1],
    (str[regex[1], 1] unless prefix[1].empty?).to_s.strip
  ]
  c = !quoted.nil? && !final.nil? ? (!match[0].nil? ? 0 : 1) : (quoted.nil? && !final.nil? ? 1 : 0)
  remove ? [match[c].to_s, str.remove(regex[c])] : match[c].to_s
rescue
  remove ? ['', str] : ''
end

# Parses a term:
#   1) First quoted, and if found, returned
#   2) Then unquoted, and if found:
#   2.1) If it's a number, it's assumed to be an ID, casted to int and returned
#   2.2) Otherwise, assumed to be a string, returned
def parse_string_or_id(msg, quoted: nil, final: nil, remove: false)
  name, msg = parse_term(msg, quoted: quoted, remove: true)
  return (remove ? [name, msg] : name) if !name.empty?
  name, msg = parse_term(msg, final: final, remove: true)
  name = name.strip.to_i if is_num(name)
  return (remove ? [name, msg] : name)
rescue
  remove ? ['', msg] : ''
end

# Parse userlevel author from a message. Might return a string if a name is found,
# or an integer if an ID is found.
def parse_userlevel_author(msg, remove: false)
  name, msg = parse_term(msg, quoted: ['author id'], remove: true)
  if !name.empty? && is_num(name)
    name = name.strip.to_i
  else
    name, msg = parse_string_or_id(msg, quoted: ['by', 'author'], final: ['by'], remove: true)
    name.strip! if name.is_a?(String)
  end
  remove ? [name, msg] : name
rescue
  remove ? ['', msg] : ''
end

# Parse userlevel title from a message. Might return a string if a name is found,
# or an integer if an ID is found.
# Also, if 'full' is true, when a name is found the entire msg will be considered the name
def parse_userlevel_title(msg, remove: false, full: true)
  name, msg = parse_string_or_id(msg, quoted: ['for', 'title'], final: ['for'], remove: true)
  name.strip! if name.is_a?(String)
  if name.is_a?(String) && name.empty? && full
    name, msg = msg, ''
    name = name.strip.to_i if is_num(name)
  end
  remove ? [name, msg] : name
rescue
  remove ? ['', msg] : ''
end

# Same as above, but using both prepositions
def parse_userlevel_both(msg, remove: false, full: false)
  name, msg = parse_string_or_id(msg, quoted: ['for', 'by', 'author'], final: ['for', 'by'], remove: true)
  name.strip! if name.is_a?(String)
  if name.is_a?(String) && name.empty? && full
    name, msg = msg, ''
    name = name.strip.to_i if is_num(name)
  end
  remove ? [name, msg] : name
rescue
  remove ? ['', msg] : ''
end

# TODO: Adapt all uses of "author" in userlevels.rb to the new system, both when
# using the author directly, as well as when calling one of the functions from io.rb
# that have changed (parse_title_and_author, parse_userlevel, etc).

# The following function is supposed to modify the message!
#
# Supports querying for both titles and author names. If both are present, at
# least one should go in quotes, to distinguish between them (it will still work
# without quotes if the author comes before the name). The one without
# quotes must go at the end, so that everything after the particle is taken to
# be the title/author name.
#
# 'full' allows for the title to default to the whole msg if no prefix is found
def parse_title_and_author(msg, full = true)
  author, msg = parse_userlevel_author(msg, remove: true)
  title, msg = parse_userlevel_title(msg, remove: true, full: full) # Keep last! (title can be whole msg if no "for" is found)
  [title, author, msg]
end

def parse_author(msg, rais = true)
  UserlevelAuthor.parse(parse_userlevel_author(msg))
rescue
  raise if rais
  nil
end

# Parse a userlevel from a message by looking for a title or an ID, as well as
# an author or author ID, optionally.
def parse_userlevel(msg)
  # --- PARSE message elements

  title, author, msg = parse_title_and_author(msg, true)
  author = UserlevelAuthor.parse(author)

  # --- FETCH userlevel(s)
  empty = {
    query: nil,
    msg:   "You need to provide a map's title, ID, author, or author ID.",
    count: 0
  }
  query = Userlevel
  err   = ""
  count = 0

  # TODO: Use this code for the userlevel_browse function too, perhaps abstract

  if title.is_a?(Integer)
    query = Userlevel.where(id: title)
    err = "No userlevel with ID #{verbatim(title)} found."
  else
    errs = []
    if !title.empty?
      query = query.where_like('title', title[0...128])
      errs << "with title #{verbatim(title[0...128])}"
    end
    if !author.nil?
      query = query.where(author: author) 
      errs << "by author #{verbatim(author.name)}"
    end
    err = "No userlevel #{errs.join(' ')} found."
  end

  # --- Prepare return depending on map count
  ret   = ""
  count = query.count
  author = author.name if author.is_a?(UserlevelAuthor)
  case count
  when 0
    ret = err
  when 1
    query = query.first
  else
    ret = "Multiple matching maps found. Please refine terms or use the userlevel ID:"
  end
  { query: query, msg: ret, count: count, title: title.to_s, author: author.to_s }
end

# The palette may or may not be quoted, but it MUST go at the end of the command
# if it's not quoted. Only look in 'pal' if not nil. 'fallback' will default
# to the default palette if no good matches, otherwise exception.
def parse_palette(event, dflt = Map::DEFAULT_PALETTE, pal: nil, fallback: true)
  msg = event.content
  err = ""
  pal.strip! if !pal.nil?

  # Parse message for explicit palette specification
  pal, msg = parse_term(msg, quoted: ['palette'], final: ['palette'], remove: true) if pal.nil?
  ret = { msg: msg, palette: pal, error: err }

  if !ret[:palette].empty?
    themes = Map::THEMES.map(&:downcase)

    # If no perfect matches
    if !themes.include?(ret[:palette].downcase)
      # Look for partial matches
      matches = themes.select{ |t| !!t[/#{pal}/i] }
      if matches.size == 1
        ret[:palette] = matches.first 
        return ret
      end
      raise "Multiple matches found for palette `#{ret[:palette]}`#{matches.size > 10 ? " (#{matches.size} matches, showing 10)" : ''}:\n#{format_block(matches.take(10).join("\n"))}" if matches.size > 0

      # Look for approximate matches
      matches = string_distance_list_mixed(ret[:palette].downcase, themes.each_with_index.to_a.map(&:reverse)).map(&:last)
      if matches.size == 1
        ret[:palette] = matches.first
        return ret
      end
      raise "No matches found for palette `#{ret[:palette]}`. Did you mean...\n#{format_block(matches.join("\n"))}" if matches.size > 0

      # No matches whatsoever
      raise "No good matches for palette `#{ret[:palette]}` found." if !fallback
      err = "No good matches for palette `#{ret[:palette]}` found, using `#{Userlevel::DEFAULT_PALETTE}`."
      pal = ''
    end
  end

  # Fall back to default if no explicit palette
  if pal.empty?
    p = User.find_by(username: event.user.name).palette rescue nil
    pal = p || dflt
  end

  err += "\n" if !err.empty?
  { msg: msg, palette: pal, error: err }
rescue RuntimeError
  raise
rescue => e
  lex(e, 'Failed to parse palette')
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
  !!msg[/#{strict ? "(\A|\W)" : ""}\*#{strict ? "(\z|\W)" : ""}/i] || name && !!msg[/\bstar\b/i]
end

# Parse type of leaderboard (highscore, speedrun, dual, ...)
# Second parameter determines the default
def parse_board(msg, dflt = nil, dual: false)
  board = nil
  board = 'dual' if !!msg[/\bdual\b/i] && dual
  board = 'hs'   if !!msg[/\bhs\b/i] || !!msg[/\bhigh\s*score\b/i]
  board = 'gm'   if !!msg[/\bng\b/i] || !!msg[/\bg--(\s|$)/i]
  board = 'sr'   if !!msg[/\bsr\b/i] || !!msg[/\bspeed\s*run\b/i]
  board = dflt   if board.nil?
  board
end

# Pings a role by name (returns ping string)
def ping(rname)
  server = TEST ? $bot.servers.values.first : $bot.servers[SERVER_ID]
  if server.nil?
    log("server not found")
    return ""
  end

  role = server.roles.select{ |r| r.name == rname }.first
  if role != nil
    if role.mentionable
      return role.mention
    else
      log("role #{rname} in server #{server.name} not mentionable")
      return ""
    end
  else
    log("role #{rname} not found in server #{server.name}")
    return ""
  end
end

# Parse arguments and flags CLI-style:
# Arg names must start with a dash and be alphanumeric (underscores allowed)
# Arg values can be anything but dashes
def parse_flags(msg)
  msg.scan(/-(\w+)\s*([^-]+)?/)
     .uniq{ |e| e[0] }
     .map{ |k, v| [k, v.nil? ? nil : v.squish] }
     .to_h
     .symbolize_keys
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

def format_board(board)
  case board
  when 'hs'
    'highscore'
  when 'sr'
    'speedrun'
  when 'gm'
    'G--'
  when 'dual'
    'dual'
  else
    'highscore'
  end
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
  return type.to_s.remove('Mappack') if !type.is_a?(Array)
  type.map!{ |t| t.to_s.remove('Mappack') }
  case type.size
  when 0
    empty ? '' : 'Overall'
  when 1
    type.first
  when 2
    if type.include?('Level') && type.include?('Episode')
      'Overall'
    else
      type.map{ |t| t.to_s.downcase }.join(" and ").capitalize
    end
  when 3
    'Overall (w/ HC)'
  end
end

def format_mappack(mappack)
  !mappack.nil? ? "for `#{mappack.name}` mappack" : ''
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

def format_max(max, min = false)
  !max.nil? ? " [#{min ? 'MIN' : 'MAX'}. #{(max.is_a?(Integer) ? "%d" : "%.3f") % max}]" : ''
end

def format_author(author)
  return '' if !author.is_a?(UserlevelAuthor)
  "on maps by #{verbatim(author.name)}"
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

def format_list_score(s, board = nil)
  p_rank  = board != 'gm'
  p_score = board != 'gm'
  rankf   = board.nil? ? 'rank' : "rank_#{board}"
  scoref  = board.nil? ? 'score' : "score_#{board}"
  scale   = board == 'hs' ? 60.0 : 1
  fmt     = board == 'sr' ? "%4d" : "%7.3f"
  pad     = board.nil? ? 10 : 14
  rank_t  = p_rank ? "#{Highscoreable.format_rank(s[rankf])}: ": ''
  name_t  = s.highscoreable.name.ljust(pad, " ")
  score_t = p_score ? " - #{fmt % [s[scoref] / scale]}" : ''
  "#{rank_t}#{name_t}#{score_t}"
end

def format_level_list(levels)
  pad = levels.map{ |l| l.name.length }.max + 1
  format_block(levels.map{ |s| s.name.ljust(pad, ' ') + s.longname }.join("\n"))
end

def format_level_matches(event, msg, page, initial, matches, func)
  exact = matches[0].split(' ')[0] == 'Multiple'
  if exact # Multiple partial matches
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

def tmp_filename(name)
  File.join(Dir.tmpdir, name)
end


def tmp_file(data, name = 'result.txt', binary: false, file: true)
  tmpfile = tmp_filename(name)
  File::open(tmpfile, binary ? 'wb' : 'w', crlf_newline: !binary) do |f|
    f.write(data)
  end
  file ? File::open(tmpfile) : tmpfile
end

def send_file(event, data, name = 'result.txt', binary = false)
  return nil if data.nil?
  event.attach_file(tmp_file(data, name, binary: binary))
end
