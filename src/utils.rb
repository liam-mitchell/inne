# Library of general functions useful throughout the program

require 'active_record'
require 'damerau-levenshtein'
require 'net/http'
require 'unicode/emoji'

require_relative 'constants.rb'
require_relative 'models.rb'

if LOG_SQL
  ActiveRecord::Base.logger = Logger.new(STDOUT)
  ActiveRecord::Base.logger = Logger.new(PATH_LOG_SQL) if LOG_TO_FILE
end

# Custom logging class, that supports:
#   - 9 modes (info, error, debug, etc)
#   - 5 levels of verbosity (from silent to all)
#   - 3 outputs (terminal, file and Discord DMs)
#   - Both raw and rich format (colored, unicode, etc)
#   - Methods to config it on the fly from Discord
module Log

  MODES = {
    fatal: { long: 'FATAL', short: 'F', fmt: "\x1B[41m" }, # Red background
    error: { long: 'ERROR', short: '✗', fmt: "\x1B[31m" }, # Red
    warn:  { long: 'WARN ', short: '!', fmt: "\x1B[33m" }, # Yellow
    good:  { long: 'GOOD ', short: '✓', fmt: "\x1B[32m" }, # Green
    info:  { long: 'INFO ', short: 'i', fmt: ""         }, # Normal
    msg:   { long: 'MSG  ', short: 'm', fmt: "\x1B[34m" }, # Blue
    in:    { long: 'IN   ', short: '←', fmt: "\x1B[35m" }, # Magenta
    out:   { long: 'OUT  ', short: '→', fmt: "\x1B[36m" }, # Cyan
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

  @fancy = LOG_FANCY
  @modes = LEVELS[LOG_LEVEL] || LEVELS[:normal]
  @modes_file = LEVELS[LOG_LEVEL_FILE] || LEVELS[:quiet]

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

  # Main function to log text
  def self.write(
    text,           # The text to log
    mode,           # The type of log (info, error, debug, etc)
    app = 'BOT',    # The origin of the log (outte, discordrb, webrick, etc)
    newline: true,  # Add a newline at the end or not
    pad:     false, # Pad each line of the text to a fixed width
    fancy:   nil,   # Use rich logs (color, bold, etc)
    console: true,  # Log to the console
    file:    true,  # Log to the log file
    discord: false  # Log to the botmaster's DMs in Discord
  )
    # Return if we don't need to log anything
    mode = :info if !MODES.key?(mode)
    log_to_console = LOG_TO_CONSOLE && console && @modes.include?(mode)
    log_to_file    = LOG_TO_FILE    && file    && @modes_file.include?(mode)
    log_to_discord = LOG_TO_DISCORD && discord
    return text if !log_to_console && !log_to_file && !log_to_discord

    # Determine parameters
    fancy = @fancy if ![true, false].include?(fancy)
    fancy = false if !LOG_FANCY
    stream = STDOUT
    stream = STDERR if [:warn, :error, :fatal].include?(mode)
    m = MODES[mode] || MODES[:info]

    # Message prefixes (timestamp, symbol, source app)
    date = Time.now.strftime(DATE_FORMAT_LOG)
    type = {
      fancy: "#{m[:fmt]}#{BOLD}#{m[:short]}#{RESET}",
      plain: "[#{m[:long]}]".ljust(7, ' ')
    }
    app = " (#{app.ljust(3, ' ')[0...3]})"
    app = {
      fancy: LOG_APPS ? "#{BOLD}#{app}#{RESET}" : '',
      plain: LOG_APPS ? app : ''
    }

    # Format text
    header = {
      fancy: "[#{date}] #{type[:fancy]}#{app[:fancy]} ",
      plain: "[#{date}] #{type[:plain]}#{app[:plain]} ",
    }
    lines = {
      fancy: text.split("\n").map{ |l| (header[:fancy] + "#{m[:fmt]}#{l}#{RESET}").strip },
      plain: text.split("\n").map{ |l| (header[:plain] + l).strip }
    }
    lines = {
      fancy: lines[:fancy].map{ |l| l.ljust(LOG_PAD, ' ') },
      plain: lines[:plain].map{ |l| l.ljust(LOG_PAD, ' ') }
    } if pad
    msg = {
      fancy: "\r" + lines[:fancy].join("\n"),
      plain: "\r" + lines[:plain].join("\n")
    }

    # Log to the terminal, if specified
    if log_to_console
      t_msg = fancy ? msg[:fancy] : msg[:plain]
      newline ? stream.puts(t_msg) : stream.print(t_msg) 
      stream.flush
    end

    # Log to a file, if specified and possible
    if log_to_file
      if File.size?(PATH_LOG_FILE).to_i >= LOG_FILE_MAX
        File.rename(PATH_LOG_FILE, PATH_LOG_OLD)
        warn("Log file was filled!", file: false, discord: true)
      end
      File.write(PATH_LOG_FILE, msg[:plain].strip + "\n", mode: 'a')
    end

    # Log to Discord DMs, if specified
    discord(text) if log_to_discord

    # Return original text
    text
  end

  # Handle exceptions
  def self.exception(e, msg = '', **kwargs)
    write("#{msg}: #{e}", :error, kwargs)
    write(e.backtrace.join("\n"), :debug) if LOG_BACKTRACES
  end

  # Send DM to botmaster
  def self.discord(msg)
    botmaster.pm.send_message(msg) if LOG_TO_DISCORD rescue nil
  end

  # Clear the current terminal line
  def self.clear
    write('', :info, newline: false, pad: true)
  end
end

# Shortcuts for different logging methods
def log   (msg, **kwargs) Log.write(msg, :info,  kwargs) end
def warn  (msg, **kwargs) Log.write(msg, :warn,  kwargs) end
def err   (msg, **kwargs) Log.write(msg, :error, kwargs) end
def msg   (msg, **kwargs) Log.write(msg, :msg,   kwargs) end
def succ  (msg, **kwargs) Log.write(msg, :good,  kwargs) end
def dbg   (msg, **kwargs) Log.write(msg, :debug, kwargs) end
def lin   (msg, **kwargs) Log.write(msg, :in,    kwargs) end
def lout  (msg, **kwargs) Log.write(msg, :out,   kwargs) end
def fatal (msg, **kwargs) Log.write(msg, :fatal, kwargs) end
def lex (e, msg = '', **kwargs)    Log.exception(e, msg) end
def ld  (msg)                      Log.discord(msg)      end

# Make a request to N++'s server.
# Since we need to use an open Steam ID, the function goes through all
# IDs until either an open is found (and stored), or the list ends and we fail.
#   - uri_proc:  A Proc returning the exact URI, takes Steam ID as parameter
#   - data_proc: A Proc that handles response data before returning it
#   - err:       Error string to log if the request fails
#   - vargs:     Extra variable arguments to pass to the uri_proc
#   - fast:      Only try the recently active Steam IDs
def get_data(uri_proc, data_proc, err, *vargs, fast: false)
  attempts ||= 0
  ids = User.where.not(steam_id: nil)
  ids = ids.where(active: true) if fast
  count = ids.count
  i = 0
  initial_id = GlobalProperty.get_last_steam_id
  response = Net::HTTP.get_response(uri_proc.call(initial_id, *vargs))
  while response.body == INVALID_RESP
    GlobalProperty.update_last_steam_id(fast)
    i += 1
    break if GlobalProperty.get_last_steam_id == initial_id || i > count
    response = Net::HTTP.get_response(uri_proc.call(GlobalProperty.get_last_steam_id, *vargs))
  end
  return nil if response.body == INVALID_RESP
  raise "502 Bad Gateway" if LOG_DOWNLOAD_ERRORS && response.code.to_i == 502
  GlobalProperty.activate_last_steam_id
  data_proc.call(response.body)
rescue => e
  if (attempts += 1) < RETRIES
    err("#{err}: #{e}") if LOG_DOWNLOAD_ERRORS
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
rescue => e
  lex(e, 'Failed to forward request to Metanet')
  nil
end

# Execute code block in another process
#
# Technical note: We disconnect from the db before forking and reconnect after,
# because otherwise the forked process inherits the same connection, and if
# it's broken there (e.g. by an unhandled exception), then it's also broken
# in the parent, thus losing connection until we restart.
def _fork
  read, write = IO.pipe
  ActiveRecord::Base.connection.disconnect!

  pid = fork do
    read.close
    result = yield
    Marshal.dump(result, write)
    exit!(0)
  rescue => e
    lex(e, 'Error in forked process')
    nil
  end

  ActiveRecord::Base.connection.reconnect!
  write.close
  result = read.read
  Process.wait(pid)
  raise 'Child failed' if result.empty?
  Marshal.load(result)
rescue RuntimeError
  raise
rescue => e
  lex(e, 'Forking failed')
end

# Execute a shell command
def shell(command, output: false)
  command += ' > /dev/null 2>&1' if !output
  system(command)
rescue => e
  lex(e, "Failed to execute shell command: #{command}")
end

def release_connection
  #ActiveRecord::Base.connection_pool.release_connection
  ActiveRecord::Base.connection.disconnect!
end

# Wrapper to benchmark a piece of code
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
    dbg("Benchmark #{msg.nil? ? ("%02d" % @step) : msg}: #{"%8.3fms" % (int * 1000)} (Total: #{"%8.3fms" % (@total * 1000)}).")
  end
end

# Wrapper to do memory profiling for a piece of code
def profile(action, name = '')
  case action
  when :start
    MemoryProfiler.start
  when :stop
    MemoryProfiler.stop.pretty_print(
      to_file:         File.join(DIR_LOGS, 'memory_profile.txt'),
      scale_bytes:     true,
      detailed_report: true,
      normalize_paths: true
    )
  end
rescue => e
  lex(e, 'Failed to do memory profiling')
end

# Send or edit a Discord message in parallel
# We actually send an array of messages, not only so that we can edit them all,
# but mainly because that way we actually can edit the original message object.
# (i.e. simulate pass-by-reference via encapsulation)
def concurrent_edit(event, msgs, content)
  Thread.new do
    msgs.map!{ |msg|
      msg.nil? ? event.send_message(content) : msg.edit(content)
    }
  rescue
    msgs
  end
rescue
  msgs
end

# Return system's memory info in MB as a hash (Linux only)
def meminfo
  File.read("/proc/meminfo").split("\n").map{ |f| f.split(':') }
      .map{ |name, value| [name, value.to_i / 1024.0] }.to_h
rescue
  {}
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

# Ensure a string is filename-safe (printable ASCII only, minus Windows's
# reserved characters)
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

# Converts any type input to an array of type classes
# Also converts types to mappack ones if necessary
def normalize_type(type, empty: false, mappack: false)
  type = DEFAULT_TYPES.map(&:constantize) if type.nil?
  type = [type] if !type.is_a?(Array)
  type = DEFAULT_TYPES.map(&:constantize) if !empty && type.empty?
  type.map{ |t| mappack && t.to_s[0..6] != 'Mappack' ? "Mappack#{t.to_s}".constantize : t }
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

# Finds the maximum value a player can reach in a certain ranking
# If 'empty' we allow no types, otherwise default to Level and Episode
def find_max(rank, types, tabs, empty = false, mappack = nil, board = 'hs')
  # Normalize params
  types = normalize_type(types, empty: empty, mappack: !mappack.nil?)

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

# Calculate episode splits based on the 5 level scores
def splits_from_scores(scores, start: 90.0, factor: 1, offset: 90.0)
  acc = start
  scores.map{ |s| round_score(acc += (s / factor - offset)) }
end

def scores_from_splits(splits, offset: 90.0)
  splits.each_with_index.map{ |s, i|
    round_score(i == 0 ? s : s - splits[i - 1] + offset)
  }
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
def remove_mentions!(msg)
  msg.gsub!(/<@!?[0-9]*>\s*/, '')
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
      allowed: ['botmasters']
    }
  else
    names = Role.owners(role).pluck(:username)
    {
      granted: Role.exists(event.user.id, role),
      allowed: role.pluralize #names
    }
  end
end

def assert_permissions(event, roles = [])
  roles.push('botmaster') # Can do everything
  permissions = roles.map{ |role| check_permission(event, role) }
  granted = permissions.map{ |p| p[:granted] }.count(true) > 0
  error = "Sorry, only #{permissions.map{ |p| p[:allowed] }.flatten.to_sentence} are allowed to execute this command."
  raise error if !granted
rescue
  raise "Permission check failed"
end

def clean_userlevel_message(msg)
  msg.sub(/(for|of)?\w*userlevel\w*/i, '').squish
end

def remove_word_first(msg, word)
  msg.sub(/\w*#{word}\w*/i, '').squish
end

# Find the botmaster's Discord user
def botmaster
  $bot.servers.each{ |id, server|
    member = server.member(BOTMASTER_ID)
    return member if !member.nil?
  }
  err("Couldn't find botmaster")
  nil
rescue => e
  lex(e, "Error finding botmaster")
  nil
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
def string_distance(word1, word2, max: 3, th: 3)
  d = DamerauLevenshtein.distance(word1, word2, 1, max)
  (d - [word1.length, word2.length].min).abs < th ? nil : d
end

# DISTANCE BETWEEN STRING AND PHRASE
# Same as before, but compares a word with a phrase, but comparing word by word
#   and taking the MINIMUM (for single-word matches, which is common)
# Returns nil if the threshold is surpassed for EVERY word
def string_distance_chunked(word, phrase, max: 3, th: 3)
  phrase.split(/\W|_/i).reject{ |chunk| chunk.strip.empty? }.map{ |chunk|
    string_distance(word, chunk, max: max, th: th)
  }.compact.min
end

# DISTANCE BETWEEN WORD AND LIST
# (read 'string_distance_list_mixed' for docs)
def string_distance_list(word, list, max: 3, th: 3, chunked: false)
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

def force_restart(reason = 'Unknown reason')
  warn("Restarted outte due to: #{reason}.", discord: true)
  exec('./inne')
end

def restart(reason = 'Unknown reason')
  log("Attempting to restart outte due to: #{reason}.")
  tasks = $active_tasks.select{ |k, v| v }.to_h
  log("Waiting for active tasks to finish... (#{tasks.keys.map(&:to_s).join(', ')})") if tasks.size > 0
  sleep(5) while $active_tasks.values.count(true) > 0
  force_restart(reason)
rescue => e
  lex(e, 'Failed to restart outte', discord: true)
  sleep(5)
  retry
end
