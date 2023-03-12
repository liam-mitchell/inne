# Library of general functions useful throughout the program

require 'active_record'
require_relative 'constants.rb'
ActiveRecord::Base.logger = Logger.new(STDOUT) if LOG_SQL

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

# Convert an integer into a little endian binary string of 'size' bytes and back
def _pack(n, size)
  n.to_s(16).rjust(2 * size, "0").scan(/../).reverse.map{ |b|
    [b].pack('H*')[0]
  }.join.force_encoding("ascii-8bit")
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

def bench(action)
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
    log("Benchmark #{@step}: #{"%.3fms" % (int * 1000)} (Total: #{"%.3fms" % (@total * 1000)}).")
  end
end

# Function to pad (and possibly truncate) a string according to different
# padding methods, determined by the constants defined at the start.
# It's a general function, but with a boolean we specify if we're formatting
# player names for leaderboards in particular, in which case, the maximum
# padding length is different.
def format_string(str, padding = DEFAULT_PADDING, max_pad = MAX_PADDING, leaderboards = true)
  max_pad = !max_pad.nil? ? max_pad : (leaderboards ? MAX_PADDING : MAX_PAD_GEN)
  if SCORE_PADDING > 0 # FIXED padding mode
    "%-#{"%d" % [SCORE_PADDING]}s" % [TRUNCATE_NAME ? str.slice(0, SCORE_PADDING) : str]
  else                 # VARIABLE padding mode
    if max_pad > 0   # maximum padding supplied
      if padding > 0       # valid padding
        if padding <= max_pad 
          "%-#{"%d" % [padding]}s" % [TRUNCATE_NAME ? str.slice(0, padding) : str]
        else
          "%-#{"%d" % [max_pad]}s" % [TRUNCATE_NAME ? str.slice(0, max_pad) : str]
        end
      else                 # invalid padding
        "%-#{"%d" % [DEFAULT_PADDING]}s" % [TRUNCATE_NAME ? str.slice(0, DEFAULT_PADDING) : str]
      end
    else                 # maximum padding not supplied
      if padding > 0       # valid padding
        "%-#{"%d" % [padding]}s" % [TRUNCATE_NAME ? str.slice(0, padding) : str]
      else                 # invalid padding
        "%-#{"%d" % [DEFAULT_PADDING]}s" % [TRUNCATE_NAME ? str.slice(0, DEFAULT_PADDING) : str]
      end
    end
  end
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
def find_max_type(rank, type, tabs)
  case rank
  when :points
    (tabs.empty? ? type : type.where(tab: tabs)).count * 20
  when :avg_points
    20
  when :avg_rank
    0
  when :maxable
    HighScore.ties(type, tabs, nil, false, true).size
  when :maxed
    HighScore.ties(type, tabs, nil, true, true).size
  when :clean
    0.0
  when :score
    query = Score.where(highscoreable_type: type.to_s, rank: 0)
    query = query.where(tab: tabs) if !tabs.empty?
    query = query.sum(:score)
    query = query
    query
  else
    (tabs.empty? ? type : type.where(tab: tabs)).count
  end
end

# Finds the maximum value a player can reach in a certain ranking
# If 'empty' we allow no types, otherwise default to Level and Episode
def find_max(rank, types, tabs, empty = false)
  types = DEFAULT_TYPES.map(&:constantize) if types.nil? || !empty && types.is_a?(Array) && types.empty?
  maxes = [types].flatten.map{ |t| find_max_type(rank, t, tabs) }
  [:avg_points, :avg_rank].include?(rank) ? maxes.first : maxes.sum
end

# Finds the minimum number of scores required to appear in a certain
# average rank/point rankings
# If 'empty' we allow no types, otherwise default to Level and Episode
# If 'a' and 'b', we weight the min scores by the range size
# If 'star' then we're dealing with only * scores, and we should again be
# more gentle
def min_scores(type, tabs, empty = false, a = 0, b = 20, star = false)
  type = DEFAULT_TYPES.map(&:constantize) if type.nil? || !empty && type.empty?
  mins = [type].flatten.map{ |t|
    if tabs.empty?
      type_min = TABS[t.to_s].sum{ |k, v| v[2] }
    else
      type_min = tabs.map{ |tab| TABS[t.to_s][tab][2] if TABS[t.to_s].key?(tab) }.compact.sum
    end
    [type_min, TYPES[t.to_s][0]].min
  }.sum
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

# Permission system:
#   Support for different roles (unrelated to Discord toles). Each role can
#   be determined by whichever system we choose (Discord user IDs, Discord
#   roles, etc.). We can restrict each function to only specific roles.
#
#   Currently implemented roles:
#     1) botmaster: Only the manager of the bot can execute them (matches
#                   Discord's user ID with a constant).
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
  msg.sub(/(for|of)?\s*\w*userlevel\w*\s*/i, '').strip
end

def remove_word_first(msg, word)
  msg.sub(/\s*\w*#{word}\w*\s*/i, '').strip
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
  if last_msg.author.id == CONFIG['client_id']
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
  puts "Main channel:    #{$channel.name}."         if !$channel.nil?
  puts "Mapping channel: #{$mapping_channel.name}." if !$mapping_channel.nil?
  puts "Nv2 channel:     #{$nv2_channel.name}."     if !$nv2_channel.nil?
  puts "Content channel: #{$content_channel.name}." if !$content_channel.nil?
end
