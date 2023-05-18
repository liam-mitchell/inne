# Library of general functions useful throughout the program

require 'active_record'
require 'damerau-levenshtein'
require 'net/http'
require 'unicode/emoji'

require_relative 'constants.rb'
require_relative 'models.rb'

ActiveRecord::Base.logger = Logger.new(LOG_TO_FILE ? "log_outte_sql" : STDOUT) if LOG_SQL

# Custom logging class for the terminal, that supports:
#   - Multiple levels of verbosity (from quiet to debug)
#   - Different modes for different purposes
#   - Both raw and rich output (colored, unicode, etc)
#   - Methods to config it on the fly from Discord
module Log

  MODES = {
    fatal: { long: 'FATAL', short: 'F', fmt: "\x1B[41m" }, # Red background
    error: { long: 'ERROR', short: '✗', fmt: "\x1B[31m" }, # Red
    warn:  { long: 'WARN',  short: '!', fmt: "\x1B[33m" }, # Yellow
    good:  { long: 'GOOD',  short: '✓', fmt: "\x1B[32m" }, # Green
    info:  { long: 'INFO',  short: 'i', fmt: ""         }, # Normal
    msg:   { long: 'MSG',   short: 'm', fmt: "\x1B[34m" }, # Blue
    in:    { long: 'IN',    short: '←', fmt: "\x1B[35m" }, # Magenta
    out:   { long: 'OUT',   short: '→', fmt: "\x1B[36m" }, # Cyan
    debug: { long: 'DEBUG', short: 'D', fmt: "\x1B[90m" }  # Gray
  }

  LEVELS = {
    silent: [],
    quiet:  [:fatal, :error, :warn],
    normal: [:fatal, :error, :warn, :good, :info, :msg],
    debug:  [:fatal, :error, :warn, :good, :info, :msg, :debug],
    all:    [:fatal, :error, :warn, :good, :info, :msg, :debug, :in, :out]
  }

  BOLD  = "\x1B[1m"
  RESET = "\x1B[0m"

  @modes = LEVELS[LOG_LEVEL] || LEVELS[:normal]
  @fancy = LOG_FANCY

  def self.level(l)
   return dbg("Logging level #{l} does not exist") if !LEVELS.key?(l)
    @modes = LEVELS[l]
    dbg("Changed logging level to #{l.to_s}")
  rescue
    dbg("Failed to change logging level")
  end

  def self.fancy
    @fancy = !@fancy
    @fancy ? dbg("Enabled fancy logs") : dbg("Disabled fancy logs")
  rescue
    dbg("Failed to change logging fanciness")
  end

  def self.set_modes(modes)
    @modes = modes.select{ |m| MODES.key?(m) }
    dbg("Set logging modes to #{@modes.join(', ')}.")
  rescue
    dbg("Failed to set logging modes")
  end

  def self.change_modes(modes)
    added = []
    removed = []
    modes.each{ |m|
      next if !MODES.key?(m)
      if !@modes.include?(m)
        @modes << m
        added << m
      else
        @modes.delete(m)
        removed << m
      end
    }
    ret = []
    ret << "added logging modes #{added.join(', ')}" if !added.empty?
    ret << "removed logging modes #{removed.join(', ')}" if !removed.empty?
    dbg(ret.join("; ").capitalize)
  rescue
    dbg("Failed to change logging modes")
  end

  def self.modes
    @modes
  end

  def self.write(text, mode, app = 'OUTTE', newline: true, pad: false, fancy: nil)
    # Determine parameters
    return text if !LOG || !@modes.include?(mode)
    fancy = @fancy if ![true, false].include?(fancy)
    fancy = false if !LOG_FANCY
    stream = STDOUT
    stream = STDERR if [:warn, :error, :fatal].include?(mode)
    m = MODES[mode] || MODES[:info]

    # Message prefixes (timestamp, symbol, source app)
    date = Time.now.strftime(DATE_FORMAT_LOG)
    type = fancy ? "#{m[:fmt]}#{BOLD}#{m[:short]}#{RESET}" : "[#{m[:long]}]".ljust(7, ' ')
    app = " (#{app.ljust(5, ' ')[0...5]})"
    app = fancy ? "#{BOLD}#{app}#{RESET}" : app
    app = LOG_APPS ? app : ''

    # Format text
    header = "\r[#{date}] #{type}#{app} "
    msg = text.split("\n").map{ |l|
      header + (fancy ? "#{m[:fmt]}#{l}#{RESET}" : l).strip
    }.join("\n")
    msg = msg.ljust(120, ' ') if pad

    # Output to stream and optionally file, returns raw msg
    newline ? stream.puts(msg) : stream.print(msg)
    stream.flush
    File.write('log_outte', msg, mode: 'a') if LOG_TO_FILE
    text
  end

  # Handle exceptions
  def self.log_exception(e, msg = '')
    err("#{msg}: #{e}")
    dbg(e.backtrace.join("\n")) if LOG_BACKTRACES
  end

  def self.log_discord(msg)
    botmaster.pm.send_message(msg)
  rescue => e
    lex(e, "Couldn't DM botmaster")
  end

  # Shortcuts for each mode
  def self.log(msg, **kwargs)
    write(msg, :info, kwargs) if LOG_INFO
  end
  
  def self.warn(msg, **kwargs)
    write(msg, :warn, kwargs) if LOG_WARNINGS
  end
  
  def self.err(msg, **kwargs)
    write(msg, :error, kwargs) if LOG_ERRORS
  end

  def self.msg(msg, **kwargs)
    write(msg, :msg, kwargs) if LOG_MSGS
  end

  def self.succ(msg, **kwargs)
    write(msg, :good, kwargs) if LOG_SUCCESS
  end

  def self.dbg(msg, **kwargs)
    write(msg, :debug, kwargs) if LOG_DEBUG
  end

  def self.lin(msg, **kwargs)
    write(msg, :in, kwargs) if LOG_IN
  end

  def self.lout(msg, **kwargs)
    write(msg, :out, kwargs) if LOG_OUT
  end

  def self.fatal(msg, **kwargs)
    write(msg, :fatal, kwargs) if LOG_FATAL
  end

  def self.clear
    write('', :info, newline: false, pad: true)
  end
end

# Shortcuts for each of the Log methods
def log(msg,   **kwargs) Log.log(msg,   kwargs) end
def warn(msg,  **kwargs) Log.warn(msg,  kwargs) end
def err(msg,   **kwargs) Log.err(msg,   kwargs) end
def msg(msg,   **kwargs) Log.msg(msg,   kwargs) end
def succ(msg,  **kwargs) Log.succ(msg,  kwargs) end
def dbg(msg,   **kwargs) Log.dbg(msg,   kwargs) end
def lin(msg,   **kwargs) Log.lin(msg,   kwargs) end
def lout(msg,  **kwargs) Log.lout(msg,  kwargs) end
def fatal(msg, **kwargs) Log.fatal(msg, kwargs) end
def lex(e, msg = '')  Log.log_exception(e, msg) end
def ld(msg)           Log.log_discord(msg)      end

# Make a request to N++'s server.
# Since we need to use an open Steam ID, the function goes through all
# IDs until either an open is found (and stored), or the list ends and we fail.
#   - uri_proc:  A Proc returning the exact URI, takes Steam ID as parameter
#   - data_proc: A Proc that handles response data before returning it
#   - err:       Error string to log if the request fails
#   - vargs:     Extra variable arguments to pass to the uri_proc
def get_data(uri_proc, data_proc, err, *vargs)
  attempts ||= 0
  initial_id = GlobalProperty.get_last_steam_id
  response = Net::HTTP.get_response(uri_proc.call(initial_id, *vargs))
  while response.body == INVALID_RESP
    GlobalProperty.deactivate_last_steam_id
    GlobalProperty.update_last_steam_id
    break if GlobalProperty.get_last_steam_id == initial_id
    response = Net::HTTP.get_response(uri_proc.call(GlobalProperty.get_last_steam_id, *vargs))
  end
  return nil if response.body == INVALID_RESP
  raise "502 Bad Gateway" if response.code.to_i == 502
  GlobalProperty.activate_last_steam_id
  data_proc.call(response.body)
rescue => e
  if (attempts += 1) < RETRIES
    if SHOW_ERRORS
      err("#{err}: #{e}")
    end
    sleep(0.25)
    retry
  else
    return nil
  end
end

# Forward an arbitrary request to Metanet, return response's body if 200, nil else
def forward(req)
  return nil if req.nil?

  # Parse request elements
  host = 'dojo.nplusplus.ninja'
  path = req.request_uri.path
  path.sub!(/\/[^\/]+/, '') if path[/\/(.+?)\//, 1] != 'prod'
  body = req.body

  # Create request
  uri = URI.parse("https://#{host}#{path}?#{req.query_string}")
  case req.request_method.upcase
  when 'GET'
    new_req = Net::HTTP::Get.new(uri)
  when 'POST'
    new_req = Net::HTTP::Post.new(uri)
  else
    return nil
  end

  # Add headers and body (clean default ones first)
  new_req.to_hash.keys.each{ |h| new_req.delete(h) }
  req.header.each{ |k, v| new_req[k] = v[0] }
  new_req['host'] = host
  new_req.body = body

  # Execute request
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 5){ |http|
    http.request(new_req)
  }
  res.code.to_i != 200 ? nil : res.body
rescue
  nil
end

def botmaster
  $bot.servers.each{ |id, server|
    member = server.member(BOTMASTER_ID)
    return member if !member.nil?
  }
  nil
end

# Turn a little endian binary array into an integer
# TODO: This is just a special case of_unpack, substitute
def parse_int(bytes)
  if bytes.is_a?(Array) then bytes = bytes.join end
  bytes.unpack('H*')[0].scan(/../).reverse.join.to_i(16)
end

def to_ascii(s)
  s.encode('ASCII', invalid: :replace, undef: :replace, replace: "_")
end

# Escape problematic chars (e.g. quotes or backslashes)
def escape(str)
  str.dump[1..-2]
end

def unescape(str)
  "\"#{str}\"".undump
rescue
  str
end

def sanitize_filename(s)
  return '' if s.nil?
  s.chars.map{ |c| c.ord < 32 || c.ord > 126 ? '' : ([34, 42, 47, 58, 60, 62, 63, 92, 124].include?(c.ord) ? '_' : c) }.join
end

def normalize_name(name)
  name.split('-').map { |s| s[/\A[0-9]\Z/].nil? ? s : "0#{s}" }.join('-').upcase
end

def redash_name(matches)
  !!matches ? matches.captures.compact.join('-') : nil
end

# Verifies if an arbitrary floating point can be a valid score
def verify_score(score)
  decimal = (score * 60) % 1
  [decimal, 1 - decimal].min < 0.03
end

# Convert an integer into a little endian binary string of 'size' bytes and back
def _pack_raw(n, size)
  n.to_s(16).rjust(2 * size, "0").scan(/../).reverse.map{ |b|
    [b].pack('H*')[0]
  }.join.force_encoding("ascii-8bit")
end

def _pack(n, arg)
  if arg.is_a?(String)
    [n].pack(arg)
  else
    _pack_raw(n, arg.to_i)
  end
rescue
  _pack_raw(n, arg.to_i)
end

def _unpack(bytes, fmt = nil)
  if bytes.is_a?(Array) then bytes = bytes.join end
  if !bytes.is_a?(String) then bytes.to_s end
  i = bytes.unpack(fmt)[0] if !fmt.nil?
  i ||= bytes.unpack('H*')[0].scan(/../).reverse.join.to_i(16)
rescue
  if bytes.is_a?(Array) then bytes = bytes.join end
  bytes.unpack('H*')[0].scan(/../).reverse.join.to_i(16)
end

def to_utf8(str)
  str.bytes.reject{ |b| b < 32 || b == 127 }.map(&:chr).join.force_encoding('UTF-8').scrub('')
end

def parse_str(str)
  to_utf8(str.split("\x00")[0].to_s).strip
end

def is_num(str)
  return false if !str.is_a?(String)
  str.strip == str[/\d+/i]
end

def verbatim(str)
  str = str.to_s
  return "` `" if str.empty?
  "`#{str.gsub('`', '')}`"
end

def bench(action, msg = nil)
  @t ||= Time.now
  @total ||= 0
  @step ||= 0
  case action
  when :start
    @step = 0
    @total = 0
    @t = Time.now
  when :step
    @step += 1
    int = Time.now - @t
    @total += int
    @t = Time.now
    dbg("Benchmark #{msg.nil? ? ("%02d" % @step) : msg}: #{"%7.3fms" % (int * 1000)} (Total: #{"%7.3fms" % (@total * 1000)}).")
  end
end

# This corrects a datetime in the database when it's out of
# phase (e.g. after a long downtime of the bot).
def correct_time(time, frequency)
  time -= frequency while time > Time.now
  time += frequency while time < Time.now
  time
end

# Function to pad (and possibly truncate) a string according to different
# padding methods, determined by the constants defined at the start.
# It's a general function, but with a boolean we specify if we're formatting
# player names for leaderboards in particular, in which case, the maximum
# padding length is different.
def format_string(str, padding = DEFAULT_PADDING, max_pad = MAX_PADDING, leaderboards = true)
  # Compute maximum padding length
  max_pad = !max_pad.nil? ? max_pad : (leaderboards ? MAX_PADDING : MAX_PAD_GEN)

  # Compute actual padding length, based on the different constraints
  pad = DEFAULT_PADDING
  pad = padding if padding > 0
  pad = max_pad if max_pad > 0 && max_pad < padding
  pad = SCORE_PADDING if SCORE_PADDING > 0

  # Adjust padding if there are emojis or kanjis (characters with different widths)
  # We basically estimate their widths and cut the string at the closest integer
  # match to the desired padding
  widths = str.chars.map{ |s|
    s =~ Unicode::Emoji::REGEX ? WIDTH_EMOJI : (s =~ /\p{Han}|\p{Hiragana}|\p{Katakana}/i ? WIDTH_KANJI : 1)
  }
  total = 0
  totals = widths.map{ |w| total += w }
  width = totals.min_by{ |t| (t - pad).abs }
  chars = totals.index(width) + 1
  pad = pad > width ? chars + (pad - width).round : chars

  # Truncate and pad string
  "%-#{"%d" % [pad]}s" % [TRUNCATE_NAME ? str.slice(0, pad) : str]
end

def truncate_ellipsis(str, pad = DEFAULT_PADDING)
  str if !str.is_a?(String) || !pad.is_a?(Integer) || pad < 0
  str.length <= pad ? str : (pad > 3 ? str[0...pad - 3] + '...' : str[0...pad])
end

def pad_truncate_ellipsis(str, pad = DEFAULT_PADDING, max_pad = MAX_PAD_GEN)
  truncate_ellipsis(format_string(str, pad, max_pad, false))
end

# Converts an array of strings into a regex string that matches any of them
# with non-capturing groups (it can also take a string)
def regexize_words(words)
  return '' if !words.is_a?(Array) && !words.is_a?(String)
  words = [words] if words.is_a?(String)
  words = words.reject{ |w| !w.is_a?(String) || w.empty? }
  return '' if words.empty?
  words = '(?:' + words.map{ |w| "(?:\\b#{Regexp.escape(w.strip)}\\b)" }.join('|') + ')'
rescue
  ''
end

# sometimes we need to make sure there's exactly one valid type
def ensure_type(type)
  type.nil? ? Level : (type.is_a?(Array) ? (type.include?(Level) ? Level : type.flatten.first) : type)
end

# find the optimal score / amount of whatever rankings or stat
def find_max_type(rank, type, tabs, mappack = nil, board = 'hs')
  # Filter scores by type and tabs
  if !mappack.nil?
    type = "Mappack#{type.to_s}".constantize unless type.to_s[0..6] == 'Mappack'
    query = type.where(mappack: mappack)
  else
    query = type
  end
  query = query.where(tab: tabs) if !tabs.empty?

  # Distinguish ranking type
  case rank
  when :points
    query.count * 20
  when :avg_points
    20
  when :avg_rank
    0
  when :maxable
    Highscoreable.ties(type, tabs, nil, false, true).size
  when :maxed
    Highscoreable.ties(type, tabs, nil, true, true).size
  when :clean
    0.0
  when :score
    klass = mappack.nil? ? Score : MappackScore.where(mappack: mappack)
    rfield = mappack.nil? ? :rank : "rank_#{board}".to_sym
    sfield = mappack.nil? ? :score : "score_#{board}".to_sym
    scale  = !mappack.nil? && board == 'hs' ? 60.0 : 1.0
    query = klass.where(highscoreable_type: type.to_s, rfield => 0)
    query = query.where(tab: tabs) if !tabs.empty?
    query = query.sum(sfield) / scale
    !mappack.nil? && board == 'sr' ? query.to_i : query.to_f
  else
    query.count
  end
end

# Converts any type input to an array of type classes
# Also converts types to mappack ones if necessary
def normalize_type(type, empty: false, mappack: false)
  types = DEFAULT_TYPES.map(&:constantize) if types.nil?
  types = [types] if !types.is_a?(Array)
  types = DEFAULT_TYPES.map(&:constantize) if !empty && types.empty?
  types.map{ |t| mappack && t.to_s[0..6] != 'Mappack' ? "Mappack#{t.to_s}".constantize : t }
end

# Finds the maximum value a player can reach in a certain ranking
# If 'empty' we allow no types, otherwise default to Level and Episode
def find_max(rank, types, tabs, empty = false, mappack = nil, board = 'hs')
  # Normalize params
  type = normalize_type(type, empty: empty, mappack: !mappack.nil?)

  # Compute type-wise maxes, and add
  maxes = [types].flatten.map{ |t| find_max_type(rank, t, tabs, mappack, board) }
  [:avg_points, :avg_rank].include?(rank) ? maxes.first : maxes.sum
end

# Finds the minimum number of scores required to appear in a certain
# average rank/point rankings
# If 'empty' we allow no types, otherwise default to Level and Episode
# If 'a' and 'b', we weight the min scores by the range size
# If 'star' then we're dealing with only * scores, and we should again be
# more gentle
def min_scores(type, tabs, empty = false, a = 0, b = 20, star = false, mappack = nil)
  # We ignore mappack mins for now
  return 0 if !mappack.nil?

  # Normalize types
  types = normalize_type(type, empty: empty, mappack: !mappack.nil?)

  # Compute mins per type, and add
  mins = types.map{ |t|
    if tabs.empty?
      type_min = TABS[t.to_s].sum{ |k, v| v[2] }
    else
      type_min = tabs.map{ |tab| TABS[t.to_s][tab][2] if TABS[t.to_s].key?(tab) }.compact.sum
    end
    [type_min, TYPES[t.to_s][:min_scores]].min
  }.sum

  # Compute final count
  c = star ? 1 : b - a
  ([mins, MAXMIN_SCORES].min * c / 20.0).to_i
end

# round float to nearest frame
def round_score(score)
  score.is_a?(Integer) ? score : (score * 60).round / 60.0
end

# weighed average
def wavg(arr, w)
  return -1 if arr.size != w.size
  arr.each_with_index.map{ |a, i| a*w[i] }.sum.to_f / w.sum
end

def get_avatar
  GlobalProperty.find_by(key: 'avatar').value
end

def set_avatar(str)
  GlobalProperty.find_by(key: 'avatar').update(value: str)
end

def numlen(n, float = true)
  n.to_i.to_s.length + (float ? 4 : 0)
end

# Conditionally pluralize word
# If 'pad' we pad string to longest between singular and plural, for alignment
def cplural(word, n, pad = false)
  sing = word
  plur = word.pluralize
  word = n == 1 ? sing : plur
  pad  = [sing, plur].map(&:length).max
  "%-#{pad}s" % word
end

# Strip off the @outte++ mention, if present
# IDs might have an exclamation mark
def remove_mentions(msg)
  msg.gsub(/<@!?[0-9]*>\s*/, '')
end

def remove_command(msg)
  msg.sub(/^!\w+\s*/i, '').strip
end

# Computes the name of a highscoreable based on the ID and type, e.g.:
# Type = 0, ID = 2637 ---> SU-C-09-02
# The complexity of this function lies in:
#   1) The type itself (Level, Episode, Story) changes the computation.
#   2) Only some tabs have X row.
#   3) Only some tabs are secret.
#   4) Lastly, and perhaps most importantly, some tabs in Coop and Race are
#      actually split in multiple files, with the corresponding bits of
#      X row staggered at the end of each one.
# NOTE: Some invalid IDs will return valid names rather than nil, e.g., if
# type is story and ID = 120, it will return "!-00", a non-existing story.
# This is a consequence of the algorithm, but it's harmless if only correct
# IDs are inputted.
def compute_name(id, type)
  return nil if ![0, 1, 2].include?(type)
  f = 5 ** type # scaling factor

  # Fetch corresponding tab
  tab = TABS_NEW.find{ |_, t| (t[:start]...t[:start] + t[:size]).include?(id * f) }
  return nil if tab.nil?
  tab = tab[1]

  # Get stories out of the way
  return "#{tab[:code]}-#{"%02d" % (id - tab[:start] / 25)}" if type == 2

  # Compute offset in tab and file
  tab_offset = id - tab[:start] / f
  file_offset = tab_offset
  file_count = tab[:files].values[0] / f
  tab[:files].values.inject(0){ |sum, n|
    if sum <= tab_offset
      file_offset = tab_offset - sum
      file_count = n / f
    end
    sum + n / f
  }

  # If it's a secret level tab, its numbering is episode-like
  if type == 0 && tab[:secret]
    type = 1
    f = 5
  end

  # Compute episode and column offset in file
  rows = tab[:x] ? 6 : 5
  file_eps = file_count * f / 5
  file_cols = file_eps / rows
  episode_offset = file_offset * f / 5
  if tab[:x] && episode_offset >= 5 * file_eps / 6
    letter = 'X'
    column_offset = episode_offset % file_cols
  else
    letter = ('A'..'E').to_a[episode_offset % 5]
    column_offset = episode_offset / 5
  end

  # Compute column (and level number)
  prev_count = tab_offset - file_offset
  prev_eps = prev_count * f / 5
  prev_cols = prev_eps / rows
  col = column_offset + prev_cols
  lvl = tab_offset % 5

  # Return name
  case type
  when 0
    "#{tab[:code]}-#{letter}-#{"%02d" % col}-#{"%02d" % lvl}"
  when 1
    "#{tab[:code]}-#{letter}-#{"%02d" % col}"
  end
end

# Permission system:
#   Support for different roles (unrelated to Discord toles). Each role can
#   be determined by whichever system we choose (Discord user IDs, Discord
#   roles, etc.). We can restrict each function to only specific roles.
#
#   Currently implemented roles:
#     1) botmaster: Only the manager of the bot can execute them (matches
#                   Discord's user ID with a constant).
#     2) dmmc: For executing the function to batch-generate screenies of DMMC.
#
#   The following functions then check if the user who tried to execute a
#   certain function belongs to any of the permitted roles for it.
def check_permission(event, role)
  case role
  when 'botmaster'
    {
      granted: event.user.id == BOTMASTER_ID,
      allowed: 'botmasters'
    }
  else
    {
      granted: Role.exists(event.user.id, role),
      allowed: Role.owners(role).pluck(:username)
    }
  end
end

def assert_permissions(event, roles = [])
  roles.push('botmaster') # Can do everything
  permissions = roles.map{ |role| check_permission(event, role) }
  granted = permissions.map{ |p| p[:granted] }.count(true) > 0
  error = "Sorry, only #{permissions.map{ |p| p[:allowed] }.join(', ')} are allowed to execute this command."
  raise error if !granted
end

def clean_userlevel_message(msg)
  msg.sub(/(for|of)?\w*userlevel\w*/i, '').squish
end

def remove_word_first(msg, word)
  msg.sub(/\w*#{word}\w*/i, '').squish
end

# Find Discord server the bot is in, by name
def find_server(name)
  $bot.servers.find{ |id, s| s.name.downcase.include?(name.downcase) } rescue nil
end

# Find Discord channel by name, server optional
def find_channel(name, server = nil)
  if server
    find_server(server).channels.find{ |c| c.name.downcase.include?(name.downcase) } rescue nil
  else
    $bot.servers.each{ |id, s|
      channel = s.channels.find{ |c| c.name.downcase.include?(name.downcase) }
      return channel if !channel.nil?
    }
    return nil
  end
rescue
  nil
end

# Find emoji by ID or name
def find_emoji(key, server = nil)
  server = server || $bot.servers[SERVER_ID] || $bot.servers.first
  return if server.nil?
  if key.is_a?(Integer)
    server.emojis[key]
  elsif key.is_a?(String)
    server.emojis.find{ |id, e| e.name.downcase.include?(key.downcase) }[1]
  else
    nil
  end
rescue
  nil
end

# React to a Discord msg (by ID) with an emoji (by Unicode or name)
def react(channel, msg_id, emoji)
  channel = find_channel(channel) rescue nil
  raise 'Channel not found' if channel.nil?
  msg = channel.message(msg_id.to_i) rescue nil
  raise 'Message not found' if msg.nil?
  emoji = find_emoji(emoji, channel.server) if emoji.ascii_only? rescue nil
  raise 'Emoji not found' if emoji.nil?
  msg.react(emoji)
end

def unreact(channel, msg_id, emoji = nil)
  channel = find_channel(channel) rescue nil
  raise 'Channel not found' if channel.nil?
  msg = channel.message(msg_id.to_i) rescue nil
  raise 'Message not found' if msg.nil?
  if emoji.nil?
    msg.my_reactions.each{ |r|
      emoji = r.name.ascii_only? ? find_emoji(r.name, channel.server) : r.name
      msg.delete_own_reaction(emoji)
    }
  else
    emoji = find_emoji(emoji, channel.server) if emoji.ascii_only? rescue nil
    raise 'Emoji not found' if emoji.nil?
    msg.delete_own_reaction(emoji)
  end
end

# DISTANCE BETWEEN STRINGS
# * Find distance between two strings using the classic Damerau-Levenshtein
# * Returns nil if the threshold is surpassed
# * Read 'string_distance_list_mixed' for detailed docs
def string_distance(word1, word2, max: 3, th: nil)
  d = DamerauLevenshtein.distance(word1, word2, 1, max)
  (d - [word1.length, word2.length].min).abs < th ? nil : d
end

# DISTANCE BETWEEN STRING AND PHRASE
# Same as before, but compares a word with a phrase, but comparing word by word
#   and taking the MINIMUM (for single-word matches, which is common)
# Returns nil if the threshold is surpassed for EVERY word
def string_distance_chunked(word, phrase, max: 3, th: nil)
  phrase.split(/\W|_/i).reject{ |chunk| chunk.strip.empty? }.map{ |chunk|
    string_distance(word, chunk, max: max, th: th)
  }.compact.min
end

# DISTANCE BETWEEN WORD AND LIST
# (read 'string_distance_list_mixed' for docs)
def string_distance_list(word, list, max: 3, th: nil, chunked: false)
  # Determine if IDs have been provided
  ids = list[0].is_a?(Array)
  # Sort and group by distance, rejecting invalids
  list = list.each_with_index.map{ |n, i|
                if chunked
                  [string_distance_chunked(word, ids ? n[1] : n, max: max, th: th), n]
                else
                  [string_distance(word, ids ? n[1] : n, max: max, th: th), n]
                end
              }
              .reject{ |d, n| d.nil? || d > max || (!th.nil? && (d - (ids ? n[1] : n).length).abs < th) }
              .group_by{ |d, n| d }
              .sort_by{ |g| g[0] }
              .map{ |g| [g[0], g[1].map(&:last)] }
              .to_h
  # Complete the hash with the distance values that might not have appeared
  # (this allows for more consistent use of the list, e.g., when zipping)
  (0..max).each{ |i| list[i] = [] if !list.key?(i) }
  list
end

# DISTANCE-MATCH A STRING IN A LIST
#   --- Description ---
# Sort list of strings based on a Damerau-Levenshtein-ish distance to a string.
#
# The list may be provided as:
#   A list of strings
#   A list of pairs, where the string is the second element
# This is used when there may be duplicate strings that we don't want to
# ditch, in which case the first element would be the ID that makes them
# unique. Obviously, this is done with level and player names in mind, that
# may have duplicates.
#
# The comparison between strings will be performed both normally and 'chunked',
# which splits the strings in the list in words. These resulting lists are then
# zipped (i.e. first distance 0, then chunked distance 0, the distance 1, etc.)
#   --- Parameters ---
# word       - String to match in the list
# list       - List of strings / pairs to match in
# min        - Minimum distance, all matches below this distance are keepies
# max        - Maximum distance, all matches above this distance are ignored
# th         - Threshold of maximum difference between the calculated distance
#              and the string length to consider. The reason we do this is to
#              ignore trivial results, eg, the distance between 'old' and 'new'
#              is 3, not because the words are similar, but because they're only
#              3 characters long
# soft_limit - Limit of matches to show, assuming there aren't more keepies
# hard_limit - Limit of matches to show, even if there are more keepies
# Returns nil if the threshold is surpassed
def string_distance_list_mixed(word, list, min: 1, max: 3, max2: 2, th: 3, soft_limit: 10, hard_limit: 20)
  matches1 = string_distance_list(word, list, max: max,  th: th, chunked: false)
  matches2 = string_distance_list(word, list, max: max2, th: th, chunked: true)
  max = [max, max2].max
  matches = (0..max).map{ |i| [i, ((matches1[i] || []) + (matches2[i] || [])).uniq(&:first)] }.to_h
  keepies = matches.select{ |k, v| k <= min }.values.map(&:size).sum
  to_take = [[keepies, soft_limit].max, hard_limit].min
  matches.values.flatten(1).take(to_take)
end

# This function sets up the potato parameters correctly in case outte was closed,
# so that a chain of fruits may not be broken
def fix_potato
  last_msg = $nv2_channel.history(1)[0] rescue nil
  $last_potato = last_msg.timestamp.to_i rescue Time.now.to_i
  if last_msg.author.id == $config['discord_client']
    $potato = ((FRUITS.index(last_msg.content) + 1) % FRUITS.size) rescue 0
  end
rescue
  nil
end

def set_channels(event = nil)
  if !event.nil?
    $channel         = event.channel
    $mapping_channel = event.channel
    $nv2_channel     = event.channel
    $content_channel = event.channel
  elsif !TEST
    channels = $bot.servers[SERVER_ID].channels
    $channel         = channels.find{ |c| c.id == CHANNEL_ID }
    $mapping_channel = channels.find{ |c| c.id == USERLEVELS_ID }
    $nv2_channel     = channels.find{ |c| c.id == NV2_ID }
    $content_channel = channels.find{ |c| c.id == CONTENT_ID }
  else
    return
  end
  fix_potato
  log("Main channel:    #{$channel.name}")         if !$channel.nil?
  log("Mapping channel: #{$mapping_channel.name}") if !$mapping_channel.nil?
  log("Nv2 channel:     #{$nv2_channel.name}")     if !$nv2_channel.nil?
  log("Content channel: #{$content_channel.name}") if !$content_channel.nil?
end

def leave_unknown_servers
  names = []
  $bot.servers.each{ |id, s|
    if !SERVER_WHITELIST.include?(id)
      names << s.name
      s.leave
    end
  }
  warn("Left #{names.count} unknown servers: #{names.join(', ')}") if names.count > 0
end