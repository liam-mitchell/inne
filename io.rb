# This file contain methods to both parse and format crucial parts of messages,
# like levels, players, tabs, types, times, etc.
# Both messages.rb and userlevels.rb make use of it.

LEVEL_PATTERN   = /S[ILU]?-[ABCDEX]-[0-9][0-9]?-[0-9][0-9]?|[?!]-[ABCDEX]-[0-9][0-9]?/i
EPISODE_PATTERN = /S[ILU]?-[ABCDEX]-[0-9][0-9]?/i
STORY_PATTERN   = /S[ILU]?-[0-9][0-9]?/i
NAME_PATTERN    = /(for|of) (.*)[\.\?]?/i

def parse_type(msg)
  (msg[/level/i] ? Level : (msg[/episode/i] ? Episode : ((msg[/\bstory\b/i] || msg[/\bcolumn/i] || msg[/hard\s*core/i] || msg[/\bhc\b/i]) ? Story : nil)))
end

def normalize_name(name)
  name.split('-').map { |s| s[/\A[0-9]\Z/].nil? ? s : "0#{s}" }.join('-').upcase
end

# explicit: players will only be parsed if they appear explicitly, without inferring from their user, otherwise nil
# enforce: a player MUST be supplied explicitly, otherwise exception
def parse_player(msg, username, userlevel = false, explicit = false, enforce = false)
  p = msg[/(for|of) (.*)[\.\?]?/i, 2]
  playerClass = userlevel ? UserlevelPlayer : Player

  # We make sure to only return players with metanet_ids, ie., with highscores.
  if p.nil?
    if explicit
      if enforce
        raise "You need to specify a player using `for/of PLAYERNAME` for this function."
      else
        nil
      end
    else
      raise "I couldn't find a player with your username! Have you identified yourself (with '@outte++ my name is <N++ display name>')?" unless User.exists?(username: username)
      player = playerClass.where.not(metanet_id: nil).find_by(name: User.find_by(username: username).player.name)
      raise "#{p} doesn't have any high scores! Either you misspelled the name, or they're exceptionally bad..." unless !player.nil?
      player
    end
  else
    player = playerClass.where.not(metanet_id: nil).find_by(name: p)
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
  elsif !msg[/(column of the month|cotm)/].nil?
    ret = get_current(Story)
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

# We're basically building a regex string similar to: /("|“|”)([^"“”]*)("|“|”)/i
# Which parses a term in between different types of quotes
def parse_term
  quotes = ["\"", "“", "”"]
  string = "("
  quotes.each{ |quote| string += quote + "|" }
  string = string[0..-2] unless quotes.length == 0
  string += ")([^"
  quotes.each{ |quote| string += quote }
  string += "]*)("  
  quotes.each{ |quote| string += quote + "|" }
  string = string[0..-2] unless quotes.length == 0
  string += ")"
  string
end

def parse_userlevel_author(msg)
  msg[/((by)|(author))\s*#{parse_term}/i, 5] || ""
end

def parse_global(msg)
  !!msg[/global/i] || !!msg[/full/i]
end

def parse_newest(msg)
  !!msg[/newest/i]
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

def format_global(full)
  full ? "global " : "newest "
end

def format_full(full)
  full ? "full " : ""
end

def format_max(max)
  "[MAX. #{(max.is_a?(Integer) ? "%d" : "%.3f") % max}]"
end

def send_file(event, data, name = "result.txt", binary = false)
  tmpfile = File.join(Dir.tmpdir, name)
  File::open(tmpfile, "w", crlf_newline: !binary) do |f|
    f.write(data)
  end
  event.attach_file(File::open(tmpfile))
end
