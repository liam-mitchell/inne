require 'active_record'
require 'net/http'
require 'chunky_png' # for screenshot generation
#require 'oily_png'
require_relative 'constants.rb'
include ChunkyPNG::Color

ActiveRecord::Base.logger = Logger.new(STDOUT) if LOG_SQL

# Turn a little endian binary array into an integer
def parse_int(bytes)
  if bytes.is_a?(Array) then bytes = bytes.join end
  bytes.unpack('H*')[0].scan(/../).reverse.join.to_i(16)
end

# Reformat date strings received by queries to the server
def format_date(date)
  date.gsub!(/-/,"/")
  date[-6] = " "
  date = date[2..-1]
  date[0..7].split("/").reverse.join("/") + date[-6..-1]
end

def to_ascii(s)
  s.encode('ASCII', invalid: :replace, undef: :replace, replace: "_")
end

# Convert an integer into a little endian binary string of 'size' bytes and back
def _pack(n, size)
  n.to_s(16).rjust(2 * size, "0").scan(/../).reverse.map{ |b|
    [b].pack('H*')[0]
  }.join.force_encoding("ascii-8bit")
end

def _unpack(bytes)
  if bytes.is_a?(Array) then bytes = bytes.join end
  bytes.unpack('H*')[0].scan(/../).reverse.join.to_i(16)
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

# sometimes we need to make sure there's exactly one valid type
def ensure_type(type)
  (type.nil? || type.is_a?(Array)) ? Level : type
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
def find_max(rank, types, tabs)
  types = [Level, Episode] if types.nil?
  maxes = [types].flatten.map{ |t| find_max_type(rank, t, tabs) }
  [:avg_points, :avg_rank].include?(rank) ? maxes.first : maxes.sum
end

# Finds the minimum number of scores required to appear in a certain
# average rank/point rankings
def min_scores(type, tabs)
  type = [Level, Episode] if type.nil?
  mins = [type].flatten.map{ |t|
    if tabs.empty?
      type_min = TABS[t.to_s].sum{ |k, v| v[2] }
    else
      type_min = tabs.map{ |tab| TABS[t.to_s][tab][2] if TABS[t.to_s].key?(tab) }.compact.sum
    end
    [type_min, TYPES[t.to_s][0]].min
  }.sum
  [mins, MAXMIN_SCORES].min
end

# round float to nearest frame
def round_score(score)
  (score * 60).round / 60.0
end

# weighed average
def wavg(arr, w)
  return -1 if arr.size != w.size
  arr.each_with_index.map{ |a, i| a*w[i] }.sum.to_f / w.sum
end

# ActionRow builder with a Select Menu for the mode
def interaction_add_select_menu_mode(view, mode = nil)
  view = Discordrb::Webhooks::View.new if view.nil?
  view.row{ |r|
    r.select_menu(custom_id: 'menu:mode', placeholder: 'Mode: All', max_values: 1){ |m|
      MODES.each{ |k, v|
        m.option(label: "Mode: #{v.capitalize}", value: "menu:mode:#{v}", default: v == mode)
      }
    }
  }
ensure
  view
end
  
# ActionRow builder with a Select Menu for the tab
def interaction_add_select_menu_tab(view, tab = nil)
  view = Discordrb::Webhooks::View.new if view.nil?
  view.row{ |r|
    r.select_menu(custom_id: 'menu:tab', placeholder: 'Tab: All', max_values: 1){ |m|
      USERLEVEL_TABS.each{ |t, v|
        m.option(label: "Tab: #{v[:fullname]}", value: "menu:tab:#{v[:name]}", default: v[:name] == tab)
      }
    }
  }
ensure
  view
end

# ActionRow builder with a Select Menu for the order
def interaction_add_select_menu_order(view, order = nil)
  view = Discordrb::Webhooks::View.new if view.nil?
  view.row{ |r|
    r.select_menu(custom_id: 'menu:order', placeholder: 'Sort by: Default', max_values: 1){ |m|
      ["default", "title", "author", "date", "favs"].each{ |b|
        m.option(label: "Sort by: #{b.capitalize}", value: "menu:order:#{b}", default: b == order)
      }
    }
  }
ensure
  view
end

# ActionRow builder with a Select Menu for the alias type
def interaction_add_select_menu_alias_type(view, type = nil)
  view = Discordrb::Webhooks::View.new if view.nil?
  view.row{ |r|
    r.select_menu(custom_id: 'menu:alias', placeholder: 'Alias type', max_values: 1){ |m|
      ['level', 'player'].each{ |b|
        m.option(label: "#{b.capitalize} aliases", value: "menu:alias:#{b}", default: b == type)
      }
    }
  }
ensure
  view
end

# ActionRow builder with Buttons for page navigation
def interaction_add_button_navigation(view, page = 1, pages = 1)
  view = Discordrb::Webhooks::View.new if view.nil?
  view.row{ |r|
    p = "#{page} / #{pages}"
    r.button(label: "❙❮", style: :primary,   disabled: page == 1,      custom_id: 'button:nav:-1000000000')
    r.button(label: "❮",  style: :primary,   disabled: page == 1,      custom_id: 'button:nav:-1')
    r.button(label: p,    style: :secondary, disabled: true,           custom_id: 'button:nav:page')
    r.button(label: "❯",  style: :primary,   disabled: page == pages,  custom_id: 'button:nav:1')
    r.button(label: "❯❙", style: :primary,   disabled: page == pages,  custom_id: 'button:nav:1000000000')
  }
ensure
  view
end

# Function to send messages specifically when they have interactions attached
# (i.e. buttons or select menus). At the moment, there is no way to to attach
# interactions to a message and use << to prevent rate limiting, so we need to
# either send a new message, or edit the current one. Also, the originating
# events are different (MentionEvent or PrivateMessageEvent if its a new
# message, and ButtonEvent or SelectMenuEvent if its an existing message),
# so we need to access different methods with different syntax.
def send_message_with_interactions(event, msg, view = nil, edit = false)
  if edit # ButtonEvent / SelectMenuEvent
    event.update_message(content: msg, components: view)
  else # MentionEvent / PrivateMessageEvent
    event.channel.send_message(msg, false, nil, nil, nil, nil, view)
  end
end

def craft_userlevel_browse_msg(event, msg, page: 1, pages: 1, order: nil, tab: nil, mode: nil, edit: false)
  # Normalize pars
  order = "default" if order.nil? || order.empty?
  order = order.downcase.split(" ").first
  order = "date" if order == "id"
  tab = "all" if !USERLEVEL_TABS.map{ |t, v| v[:name] }.include?(tab)
  mode = "solo" if !MODES.values.include?(mode.to_s.downcase)
  # Create and fill component collection (View)
  view = Discordrb::Webhooks::View.new
  interaction_add_button_navigation(view, page, pages)
  interaction_add_select_menu_order(view, order)
  interaction_add_select_menu_tab(view, tab)
  interaction_add_select_menu_mode(view, mode)
  # Send
  send_message_with_interactions(event, msg, view, edit)
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
  when :botmaster
    {
      granted: event.user.id == BOTMASTER_ID,
      error:   'the botmasters'
    }
  end
end

def check_permissions(event, roles)
  permissions = roles.map{ |role| check_permission(event, role) }
  {
    granted: permissions.map{ |p| p[:granted] }.count(true) > 0,
    error:   "Sorry, only #{permissions.map{ |p| p[:error] }.join(', ')} are allowed to execute this command."
  }
end

def remove_word_first(msg, word)
  msg.sub(/\w*#{word}\w*/i, '')
end

module HighScore

  def self.format_rank(rank)
    "#{rank < 10 ? '0' : ''}#{rank}"
  end

  # everything in the "spreads" and "ties" functions has been carefully
  # benchmarked so, though unelegant, it's the most efficient set of
  # sql queries
  def self.spreads(n, type, tabs, small = false, player_id = nil)
    n = n.clamp(0,19)
    type = ensure_type(type)
    bench(:start) if BENCHMARK
    # retrieve player's 0ths if necessary
    if !player_id.nil?
      ids = Score.where(highscoreable_type: type.to_s, rank: 0, player_id: player_id)
      ids = ids.where(tab: tabs) if !tabs.empty?
      ids = ids.pluck('highscoreable_id')
    end
    # retrieve required scores and compute spreads
    ret1 = Score.where(highscoreable_type: type.to_s, rank: 0)
    ret1 = ret1.where(tab: tabs) if !tabs.empty?
    ret1 = ret1.where(highscoreable_id: ids) if !player_id.nil?
    ret1 = ret1.pluck(:highscoreable_id, :score).to_h
    ret2 = Score.where(highscoreable_type: type.to_s, rank: n)
    ret2 = ret2.where(tab: tabs) if !tabs.empty?
    ret2 = ret2.where(highscoreable_id: ids) if !player_id.nil?
    ret2 = ret2.pluck(:highscoreable_id, :score).to_h
    ret = ret2.map{ |id, s| [id, ret1[id] - s] }
              .sort_by{ |id, s| small ? s : -s }
              .take(NUM_ENTRIES)
              .to_h
    # retrieve level names
    lnames = type.where(id: ret.keys)
                 .pluck(:id, :name)
                 .to_h
    # retrieve player names
    pnames = Score.where(highscoreable_type: type.to_s, highscoreable_id: ret.keys, rank: 0)
                  .joins("INNER JOIN players ON players.id = scores.player_id")
                  .pluck('scores.highscoreable_id', 'players.name', 'players.display_name')
                  .map{ |a, b, c| [a, [b, c]] }
                  .to_h
    ret = ret.map{ |id, s| [lnames[id], s, pnames[id][1].nil? ? pnames[id][0] : pnames[id][1]] }
    bench(:step) if BENCHMARK
    ret
  end

  # @par player_id: Exclude levels where the player already has a score
  # @par maxed:     Sort differently depending on whether we're interested in maxed or maxable
  # @par rank:      Return rankings of people with most scores in maxed / maxable levels
  def self.ties(type, tabs, player_id = nil, maxed = nil, rank = false)
    type = ensure_type(type)
    bench(:start) if BENCHMARK
    # retrieve most tied for 0th leves
    ret = Score.where(highscoreable_type: type.to_s, tied_rank: 0)
    ret = ret.where(tab: tabs) if !tabs.empty?
    ret = ret.group(:highscoreable_id)
             .order(!maxed ? 'count(id) desc' : '', :highscoreable_id)
             .having("count(id) >= #{MIN_TIES}")
             .having(!player_id.nil? ? 'amount = 0' : '')
             .pluck('highscoreable_id', 'count(id)', !player_id.nil? ? "count(if(player_id = #{player_id}, player_id, NULL)) AS amount" : '1')
             .map{ |s| s[0..1] }
             .to_h
    # retrieve total score counts for each level (to compare against the tie count and determine maxes)
    counts = Score.where(highscoreable_type: type.to_s, highscoreable_id: ret.keys)
                  .group(:highscoreable_id)
                  .order('count(id) desc')
                  .count(:id)
    # filter
    maxed ? ret.select!{ |id, c| c == counts[id] } : ret.select!{ |id, c| c < counts[id] } if !maxed.nil?

    if rank
      ret = ret.keys
    else
      # retrieve player names owning the 0ths on said level
      pnames = Score.where(highscoreable_type: type.to_s, highscoreable_id: ret.keys, rank: 0)
                    .joins("INNER JOIN players ON players.id = scores.player_id")
                    .pluck('scores.highscoreable_id', 'players.name', 'players.display_name')
                    .map{ |a, b, c| [a, [b, c]] }
                    .to_h
      # retrieve level names
      lnames = type.where(id: ret.keys)
                   .pluck(:id, :name)
                   .to_h
      ret = ret.map{ |id, c| [lnames[id], c, counts[id], pnames[id][1].nil? ? pnames[id][0] : pnames[id][1]] }
    end
    bench(:step) if BENCHMARK
    ret
  end

  def scores_uri(steam_id)
    klass = self.class == Userlevel ? "level" : self.class.to_s.downcase
    URI.parse("https://dojo.nplusplus.ninja/prod/steam/get_scores?steam_id=#{steam_id}&steam_auth=&#{klass}_id=#{self.id.to_s}")
  end

  def replay_uri(steam_id, replay_id)
    qt = [Level, Userlevel].include?(self.class) ? 0 : (self.class == Episode ? 1 : 4)
    URI.parse("https://dojo.nplusplus.ninja/prod/steam/get_replay?steam_id=#{steam_id}&steam_auth=&replay_id=#{replay_id}&qt=#{qt}")
  end

  def self.get_data(uri_proc, data_proc, err, *vargs)
    attempts ||= 0
    initial_id = get_last_steam_id
    response = Net::HTTP.get_response(uri_proc.call(initial_id, *vargs))
    while response.body == INVALID_RESP
      deactivate_last_steam_id
      update_last_steam_id
      break if get_last_steam_id == initial_id
      response = Net::HTTP.get_response(uri_proc.call(get_last_steam_id))
    end
    return nil if response.body == INVALID_RESP
    raise "502 Bad Gateway" if response.code.to_i == 502
    activate_last_steam_id
    data_proc.call(response.body)
  rescue => e
    if (attempts += 1) < RETRIES
      if SHOW_ERRORS
        err("#{err}: #{e}")
      end
      retry
    else
      return nil
    end
  end

  def get_scores
    uri  = Proc.new { |steam_id| scores_uri(steam_id) }
    data = Proc.new { |data| correct_ties(clean_scores(JSON.parse(data)['scores'])) }
    err  = "error getting scores for #{self.class.to_s.downcase} with id #{self.id.to_s}"
    HighScore::get_data(uri, data, err)
  end

  def get_replay(replay_id)
    uri  = Proc.new { |steam_id| replay_uri(steam_id, replay_id) }
    data = Proc.new { |data| data }
    err  = "error getting replay with id #{replay_id} for #{self.class.to_s.downcase} with id #{self.id.to_s}"
    HighScore::get_data(uri, data, err)
  end

  # Remove hackers and cheaters both by implementing the ignore lists and the score thresholds.
  def clean_scores(boards)
    # Remove potential duplicates
    boards.uniq!{ |s| s['user_name'] }

    # Compute score upper limit
    if self.class == Userlevel
      limit = 2 ** 32 - 1 # No limit
    else
      limit = TABS[self.class.to_s].map{ |k, v| v[1] }.max
      TABS[self.class.to_s].each{ |k, v| if v[0].include?(self.id) then limit = v[1]; break end  }
    end

    # Filter out cheated/hacked runs
    boards.reject!{ |s|
      IGNORED_PLAYERS.include?(s['user_name']) || IGNORED_IDS.include?(s['user_id']) || s['score'] / 1000.0 >= limit
    }

    # Patch old incorrect runs
    k = self.class.to_s.downcase.to_sym
    if PATCH_RUNS[k].key?(self.id)
      boards.each{ |s|
        entry = PATCH_RUNS[k][self.id]
        s['score'] += 1000 * entry[1] if s['replay_id'] <= entry[0]
      }
    end

    boards
  rescue
    boards
  end

  def save_scores(updated)
    ActiveRecord::Base.transaction do
      updated.each_with_index do |score, i|
        # Compute values, userlevels have some differences
        player = (self.class == Userlevel ? UserlevelPlayer : Player).find_or_create_by(metanet_id: score['user_id'])
        player.update(name: score['user_name'].force_encoding('UTF-8'))
        scoretime = score['score'] / 1000.0
        scoretime = (scoretime * 60.0).round if self.class == Userlevel
        # Update common values
        scores.find_or_create_by(rank: i).update(
          score:     scoretime,
          replay_id: score['replay_id'].to_i,
          player:    player,
          tied_rank: updated.find_index { |s| s['score'] == score['score'] }
        )
        # Update class-specific values
        scores.find_by(rank: i).update(tab: self.tab) if self.class != Userlevel
        # Update the archive if the run is new
        if self.class != Userlevel && Archive.find_by(replay_id: score['replay_id'], highscoreable_type: self.class.to_s).nil?
          # Update archive entry
          ar = Archive.create(
            replay_id:     score['replay_id'].to_i,
            player:        Player.find_by(metanet_id: score['user_id']),
            highscoreable: self,
            score:         (score['score'] * 60.0 / 1000.0).round,
            metanet_id:    score['user_id'].to_i, # future-proof the db
            date:          Time.now,
            tab:           self.tab
          )
          # Update demo entry
          demo = Demo.find_or_create_by(id: ar.id)
          demo.update(replay_id: ar.replay_id, htype: Demo.htypes[ar.highscoreable_type.to_s.downcase])
          demo.update_demo
        end
      end
      self.update(last_update: Time.now) if self.class == Userlevel
      self.update(scored:       true)    if self.class == Userlevel && updated.size > 0
      # Remove scores stuck at the bottom after ignoring cheaters
      scores.where(rank: (updated.size..19).to_a).delete_all
    end
  end

  def update_scores
    updated = get_scores

    if updated.nil?
      if SHOW_ERRORS
        # TODO make this use err()
        STDERR.puts "[WARNING] [#{Time.now}] failed to retrieve scores from #{scores_uri(get_last_steam_id)}"
      end
      return -1
    end

    save_scores(updated)
  rescue => e
    if SHOW_ERRORS
      err("error updating database with level #{self.id.to_s}: #{e}")
    end
    return -1
  end

  def get_replay_info(rank)
    updated = get_scores

    if updated.nil?
      if SHOW_ERRORS
        # TODO make this use err()
        STDERR.puts "[WARNING] [#{Time.now}] failed to retrieve replay info from #{scores_uri(get_last_steam_id)}"
      end
      return
    end

    updated.select { |score| !IGNORED_PLAYERS.include?(score['user_name']) }.uniq { |score| score['user_name'] }[rank]
  end

  def analyze_replay(replay_id)
    replay = get_replay(replay_id)
    demo = Zlib::Inflate.inflate(replay[16..-1])[30..-1]
    analysis = demo.unpack('H*')[0].scan(/../).map{ |b| b.to_i }[1..-1]
  end

  def correct_ties(score_hash)
    score_hash.sort_by{ |s| [-s['score'], s['replay_id']] }
  end

  def max_name_length
    scores.map{ |s| s.player.name.length }.max
  end

  def find_coolness
    bench(:start) if BENCHMARK
    max   = scores.map(&:score).max.to_i.to_s.length + 4
    s1    = scores.first.score.to_s
    s2    = scores.last.score.to_s
    d     = (0...max).find{ |i| s1[i] != s2[i] }
    if !d.nil?
      d     = -(max - d - 5) - (max - d < 4 ? 1 : 0)
      cools = scores.size.times.find{ |i| scores[i].score < s1.to_f.truncate(d) }
    else
      cools = 0
    end
    bench(:step) if BENCHMARK
    cools
  rescue => e
    puts e.backtrace
    raise
  end

  def format_scores(padding = DEFAULT_PADDING)
    max = scores.map(&:score).max.to_i.to_s.length + 4
    scores.each_with_index.map{ |s, i| s.format(padding, max, i < find_coolness) }.join("\n")
  end

  def difference(old)
    scores.map do |score|
      oldscore = old.find { |o| o['player']['name'] == score.player.name }
      change = nil

      if oldscore
        change = {rank: oldscore['rank'] - score.rank, score: score.score - oldscore['score']}
      end

      {score: score, change: change}
    end
  end

  def format_difference(old)
    diffs = difference(old)

    name_padding = scores.map{ |s| s.player.name.length }.max
    score_padding = scores.map{ |s| s.score.to_i }.max.to_s.length + 4
    rank_padding = diffs.map{ |d| d[:change] }.compact.map{ |d| d[:rank].to_i }.max.to_s.length
    change_padding = diffs.map{ |d| d[:change] }.compact.map{ |d| d[:score].to_i }.max.to_s.length + 4

    difference(old).map { |o|
      c = o[:change]
      diff = c ? "#{"++-"[c[:rank] <=> 0]}#{"%#{rank_padding}d" % [c[:rank].abs]}, +#{"%#{change_padding}.3f" % [c[:score]]}" : "new"
      "#{o[:score].format(name_padding, score_padding)} (#{diff})"
    }.join("\n")
  end
end

class Level < ActiveRecord::Base
  include HighScore
  has_many :scores, as: :highscoreable
  has_many :videos, as: :highscoreable
  has_many :challenges
  has_many :level_aliases
  belongs_to :episode
  enum tab: [:SI, :S, :SU, :SL, :SS, :SS2]

  def add_alias(a)
    LevelAlias.find_or_create_by(level: self, alias: a)
  end

  def format_name
    "#{longname} (#{name})"
  end

  def format_challenges
    pad = challenges.map{ |c| c.count }.max
    challenges.map{ |c| c.format(pad) }.join("\n")
  end
end

class Episode < ActiveRecord::Base
  include HighScore
  has_many :scores, as: :highscoreable
  has_many :videos, as: :highscoreable
  has_many :levels
  enum tab: [:SI, :S, :SU, :SL, :SS, :SS2]

  def self.cleanliness(tabs, rank = 0)
    bench(:start) if BENCHMARK
    query = !tabs.empty? ? Score.where(tab: tabs) : Score
    # retrieve level 0th sums
    lvls = query.where(highscoreable_type: 'Level', rank: 0)
                .joins('INNER JOIN levels ON levels.id = scores.highscoreable_id')
                .group('levels.episode_id')
                .sum(:score)
    # retrieve episode names
    epis = self.pluck(:id, :name).to_h
    # retrieve episode 0th scores
    ret = query.where(highscoreable_type: 'Episode', rank: 0)
               .joins('INNER JOIN episodes ON episodes.id = scores.highscoreable_id')
               .joins('INNER JOIN players ON players.id = scores.player_id')
               .pluck('episodes.id', 'scores.score', 'players.name')
               .map{ |e, s, n| [epis[e], round_score(lvls[e] - s - 360), n] }
    bench(:step) if BENCHMARK
    ret
  end

  def self.ownages(tabs)
    bench(:start) if BENCHMARK
    query = !tabs.empty? ? Score.where(tab: tabs) : Score
    # retrieve episodes with all 5 levels owned by the same person
    epis = query.where(highscoreable_type: 'Level', rank: 0)
                .joins('INNER JOIN levels ON levels.id = scores.highscoreable_id')
                .group('levels.episode_id')
                .having('cnt = 1')
                .pluck('levels.episode_id', 'MIN(scores.player_id)', 'COUNT(DISTINCT scores.player_id) AS cnt')
                .map{ |e, p, c| [e, p] }
                .to_h
    # retrieve respective episode 0ths
    zeroes = query.where(highscoreable_type: 'Episode', highscoreable_id: epis.keys, rank: 0)
                  .joins('INNER JOIN players ON players.id = scores.player_id')
                  .pluck('scores.highscoreable_id', 'players.id')
                  .to_h
    # retrieve episode names
    enames = Episode.where(id: epis.keys)
                    .pluck(:id, :name)
                    .to_h
    # retrieve player names
    pnames = Player.where(id: epis.values)
                   .pluck(:id, :name, :display_name)
                   .map{ |a, b, c| [a, [b, c]] }
                   .to_h
    # keep only matches between the previous 2 result sets to obtain true ownages
    ret = epis.reject{ |e, p| p != zeroes[e] }
              .sort_by{ |e, p| e }
              .map{ |e, p| [enames[e], pnames[p][1].nil? ? pnames[p][0] : pnames[p][1]] }
    bench(:step) if BENCHMARK
    ret
  end

  def format_name
    "#{name}"
  end

  def cleanliness(rank = 0)
    bench(:start) if BENCHMARK
    ret = [name, Score.where(highscoreable: levels, rank: 0).sum(:score) - scores[rank].score - 360, scores[rank].player.name]
    bench(:step) if BENCHMARK
    ret
  end

  def ownage
    bench(:start) if BENCHMARK
    owner = scores[0].player
    lvls = Score.where(highscoreable: levels, rank: 0)
                .joins('INNER JOIN players ON players.id = scores.player_id')
                .count("if(players.id = #{owner.id}, 1, NULL)")
    ret = [name, lvls == 5, owner.name]
    bench(:step) if BENCHMARK
    ret
  end

  def splits(rank = 0)
    acc = 90
    Level.where("UPPER(name) LIKE ?", name.upcase + '%').map{ |l| acc += l.scores[rank].score - 90 }
  rescue
    nil
  end
end

class Story < ActiveRecord::Base
  include HighScore
  has_many :scores, as: :highscoreable
  has_many :videos, as: :highscoreable
  enum tab: [:SI, :S, :SU, :SL, :SS, :SS2]

  def format_name
    "#{name}"
  end
end

class Score < ActiveRecord::Base
  belongs_to :player
  belongs_to :highscoreable, polymorphic: true
  belongs_to :level, -> { where(scores: {highscoreable_type: 'Level'}) }, foreign_key: 'highscoreable_id'
  belongs_to :episode, -> { where(scores: {highscoreable_type: 'Episode'}) }, foreign_key: 'highscoreable_id'
  belongs_to :story, -> { where(scores: {highscoreable_type: 'Story'}) }, foreign_key: 'highscoreable_id'
#  default_scope -> { select("scores.*, score * 1.000 as score")} # Ensure 3 correct decimal places
  enum tab:  [ :SI, :S, :SU, :SL, :SS, :SS2 ]

  # Alternative method to perform rankings which outperforms the Player approach
  # since we leave all the heavy lifting to the SQL interface instead of Ruby.
  def self.rank(ranking, type, tabs, ties = false, n = 0, full = false, players = [])
    return rank_exclude(ranking, type, tabs, ties, n, full, players) if !players.empty? && [:rank, :tied_rank, :points, :avg_points, :avg_rank, :avg_lead].include?(ranking)
    type = Level if ranking == :avg_lead && (type.nil? || type.is_a?(Array)) # avg lead only works with 1 type
    scores = self.where(highscoreable_type: type.nil? ? DEFAULT_TYPES : type.to_s)
    scores = scores.where(tab: tabs) if !tabs.empty?
    scores = scores.where.not(player: players) if !players.empty?
    bench(:start) if BENCHMARK

    case ranking
    when :rank
      scores = scores.where("#{ties ? "tied_rank" : "rank"} <= #{n}")
                     .group(:player_id)
                     .order('count_id desc')
                     .count(:id)
    when :tied_rank
      scores_w  = scores.where("tied_rank <= #{n}")
                        .group(:player_id)
                        .order('count_id desc')
                        .count(:id)
      scores_wo = scores.where("rank <= #{n}")
                        .group(:player_id)
                        .order('count_id desc')
                        .count(:id)
      scores = scores_w.map{ |id, count| [id, count - scores_wo[id].to_i] }
                       .sort_by{ |id, c| -c }
    when :singular
      types = (type.nil? ? DEFAULT_TYPES : [type.to_s]).map{ |t|
        ids = scores.where(rank: 1, tied_rank: n, highscoreable_type: t)
                    .pluck(:highscoreable_id)
        scores.where(rank: 0, highscoreable_type: t, highscoreable_id: ids)
              .group(:player_id)
              .count(:id)
      }
      scores = types.map(&:keys).flatten.uniq.map{ |id|
        [id, types.map{ |t| t[id].to_i }.sum]
      }.sort_by{ |id, c| -c }
    when :points
      scores = scores.group(:player_id)
                     .order("sum(#{ties ? "20 - tied_rank" : "20 - rank"}) desc")
                     .sum(ties ? "20 - tied_rank" : "20 - rank")
    when :avg_points
      scores = scores.select("count(player_id)")
                     .group(:player_id)
                     .having("count(player_id) >= #{min_scores(type, tabs)}")
                     .order("avg(#{ties ? "20 - tied_rank" : "20 - rank"}) desc")
                     .average(ties ? "20 - tied_rank" : "20 - rank")
    when :avg_rank
      scores = scores.select("count(player_id)")
                     .group(:player_id)
                     .having("count(player_id) >= #{min_scores(type, tabs)}")
                     .order("avg(#{ties ? "tied_rank" : "rank"})")
                     .average(ties ? "tied_rank" : "rank")
    when :avg_lead
      scores = scores.where(rank: [0, 1])
                     .pluck(:player_id, :highscoreable_id, :score)
                     .group_by{ |s| s[1] }
                     .map{ |h, s| [s[0][0], s[0][2] - s[1][2]] }
                     .group_by{ |s| s[0] }
                     .map{ |p, s| [p, s.map(&:last).sum / s.map(&:last).count] }
                     .sort_by{ |p, s| -s }
    when :score
      scores = scores.group(:player_id)
                     .order("sum(score) desc")
                     .sum(:score)
                     .map{ |id, c| [id, round_score(c)] }
    when :maxed
      scores = scores.where(highscoreable_id: HighScore.ties(type, tabs, nil, true, true))
                     .where("tied_rank = 0")   
                     .group(:player_id)
                     .order("count(id) desc")
                     .count(:id)
    when :maxable
      scores = scores.where(highscoreable_id: HighScore.ties(type, tabs, nil, false, true))
                     .where("tied_rank = 0")   
                     .group(:player_id)
                     .order("count(id) desc")
                     .count(:id)
    end

    scores = scores.take(NUM_ENTRIES) if !full
    # find all players in advance (better performant)
    players = Player.where(id: scores.map(&:first))
                    .map{ |p| [p.id, p] }
                    .to_h
    ret = scores.map{ |p, c| [players[p], c] }
    ret.reject!{ |p, c| c <= 0  } unless [:avg_rank, :avg_lead].include?(ranking)

    bench(:step) if BENCHMARK
    ret
  end

  # Rankings excluding specified players. Less optimized than the function above
  # because I couldn't find a way to ignore them other than loop through all levels
  # on a one by one basis.
  def self.rank_exclude(ranking, type, tabs, ties = false, n = 0, full = false, players = [])
    bench(:start) if BENCHMARK
    pids = players.map(&:id)
    p = Player.pluck(:id).map{ |id| [id, 0] }.to_h
    q = Player.pluck(:id).map{ |id| [id, 0] }.to_h
    type = [Level, Episode] if type.nil?
    t_rank = 0
    t_score = -1

    [type].flatten.each{ |t|
      (tabs.empty? ? t.all : t.where(tab: tabs)).each{ |e|
        t_rank = 0
        t_score = 3000.0
        if ranking == :avg_lead
          a_id = -1
          a_score = -1
        end
        e.scores.reject{ |s| pids.include?(s.player_id) }.sort_by{ |s| s.rank }.each_with_index{ |s, i|
          if s.score < t_score
            t_rank = i
            t_score = s.score
          end
          case ranking
          when :rank
            (ties ? t_rank : i) <= n ? p[s.player_id] += 1 : break
          when :tied_rank
            t_rank <= n ? (i <= n ? next : p[s.player_id] += 1) : break
          when :points
            p[s.player_id] += 20 - (ties ? t_rank : i)
          when :avg_points
            p[s.player_id] += 20 - (ties ? t_rank : i)
            q[s.player_id] += 1
          when :avg_rank
            p[s.player_id] += ties ? t_rank : i
            q[s.player_id] += 1
          when :avg_lead
            if i == 0
              a_id = s.player_id
              a_score = s.score
            elsif i == 1
              p[a_id] += a_score - s.score
              q[a_id] += 1
            else
              break
            end
          end
        }
      }
    }

    bench(:step) if BENCHMARK
    p = p.select{ |id, c| q[id] > (ranking == :avg_lead ? 0 : min_scores(type, tabs)) }
         .map{ |id, c| [id, c.to_f / q[id]] }
         .to_h if [:avg_points, :avg_rank, :avg_lead].include?(ranking)
    p.sort_by{ |id, c| ranking == :avg_rank ? c : -c }
     .take(NUM_ENTRIES)
     .reject{ |id, c| c == 0 unless [:avg_rank, :avg_lead].include?(ranking) }
     .map{ |id, c| [Player.find(id), c] }
  end

  def self.total_scores(type, tabs, secrets)
    bench(:start) if BENCHMARK
    tabs = (tabs.empty? ? [:SI, :S, :SL, :SU, :SS, :SS2] : tabs)
    tabs = (secrets ? tabs : tabs - [:SS, :SS2])
    ret = self.where(highscoreable_type: type.to_s, tab: tabs, rank: 0)
              .pluck('SUM(score)', 'COUNT(score)')
              .map{ |score, count| [round_score(score.to_f), count.to_i] }
    bench(:step) if BENCHMARK
    ret.first
  end

  def spread
    highscoreable.scores.find_by(rank: 0).score - score
  end

  def demo
    Demo.find_by(replay_id: replay_id, htype: Demo.htypes[highscoreable.class.to_s.downcase.to_sym])
  end

  def format(name_padding = DEFAULT_PADDING, score_padding = 0, cool = false)
    "#{HighScore.format_rank(rank)}: #{player.format_name(name_padding)} - #{"%#{score_padding}.3f" % [score]}#{cool ? " 😎" : ""}"
  end
end

# Note: Players used to be referenced by Users, not anymore. Everything has been
# structured to better deal with multiple players and/or users with the same name.
class Player < ActiveRecord::Base
  has_many :scores
  has_many :rank_histories
  has_many :points_histories
  has_many :total_score_histories
  has_many :player_aliases

  # Deprecated since it's slower, see Score::rank
  def self.rankings(&block)
    players = Player.all

    players.map { |p| [p, yield(p)] }
      .sort_by { |a| -a[1] }
  end

  def self.histories(type, attrs, column)
    attrs[:highscoreable_type] ||= ['Level', 'Episode'] # Don't include stories
    hist = type.where(attrs).includes(:player)

    ret = Hash.new { |h, k| h[k] = Hash.new { |h, k| h[k] = 0 } }

    hist.each do |h|
      ret[h.player.name][h.timestamp] += h.send(column)
    end

    ret
  end

  def self.rank_histories(rank, type, tabs, ties)
    attrs = {rank: rank, ties: ties}
    attrs[:highscoreable_type] = type.to_s if type
    attrs[:tab] = tabs if !tabs.empty?

    self.histories(RankHistory, attrs, :count)
  end

  def self.score_histories(type, tabs)
    attrs = {}
    attrs[:highscoreable_type] = type.to_s if type
    attrs[:tab] = tabs if !tabs.empty?

    self.histories(TotalScoreHistory, attrs, :score)
  end

  def self.points_histories(type, tabs)
    attrs = {}
    attrs[:highscoreable_type] = type.to_s if type
    attrs[:tab] = tabs if !tabs.empty?

    self.histories(PointsHistory, attrs, :points)
  end

  # Only works for 1 type at a time
  def self.comparison_(type, tabs, p1, p2)
    type = ensure_type(type)
    request = Score.where(highscoreable_type: type)
    request = request.where(tab: tabs) if !tabs.empty?
    t = type.to_s.downcase.pluralize
    bench(:start) if BENCHMARK
    ids = request.where(player: [p1, p2])
                 .joins("INNER JOIN #{t} ON #{t}.id = scores.highscoreable_id")
                 .group(:highscoreable_id)
                 .having('count(highscoreable_id) > 1')
                 .pluck('MIN(highscoreable_id)')
    scores1 = request.where(highscoreable_id: ids, player: p1)
                     .joins("INNER JOIN #{t} ON #{t}.id = scores.highscoreable_id")
                     .order(:highscoreable_id)
                     .pluck(:rank, :highscoreable_id, "#{t}.name", :score)
    scores2 = request.where(highscoreable_id: ids, player: p2)
                     .joins("INNER JOIN #{t} ON #{t}.id = scores.highscoreable_id")
                     .order(:highscoreable_id)
                     .pluck(:rank, :highscoreable_id, "#{t}.name", :score)
    scores = scores1.zip(scores2).group_by{ |s1, s2| s1[3] <=> s2[3] }
    s1 = request.where(player: p1)
                .where.not(highscoreable_id: ids)
                .joins("INNER JOIN #{t} ON #{t}.id = scores.highscoreable_id")
                .pluck(:rank, :highscoreable_id, "#{t}.name", :score)
                .group_by{ |s| s[0] }
                .map{ |r, s| [r, s.sort_by{ |s| s[1] }] }
                .to_h
    s2 = scores.key?(1)  ? scores[1].group_by{ |s1, s2| s1[0] }
                                   .map{ |r, s| [r, s.sort_by{ |s1, s2| s1[1] }] }
                                   .to_h
                         : {}
    s3 = scores.key?(0)  ? scores[0].group_by{ |s1, s2| s1[0] }
                                   .map{ |r, s| [r, s.sort_by{ |s1, s2| s1[1] }] }
                                   .to_h
                         : {}
    s4 = scores.key?(-1) ? scores[-1].group_by{ |s1, s2| s1[0] }
                                     .map{ |r, s| [r, s.sort_by{ |s1, s2| s2[1] }] }
                                     .to_h
                         : {}
    s5 = request.where(player: p2)
                .where.not(highscoreable_id: ids)
                .joins("INNER JOIN #{t} ON #{t}.id = scores.highscoreable_id")
                .pluck(:rank, :highscoreable_id, "#{t}.name", :score)
                .group_by{ |s| s[0] }
                .map{ |r, s| [r, s.sort_by{ |s| s[1] }] }
                .to_h
    bench(:step) if BENCHMARK
    [s1, s2, s3, s4, s5]
  end

  # Merges the results for each type using the previous method
  def self.comparison(type, tabs, p1, p2)
    type = [Level, Episode] if type.nil?
    ret = (0..4).map{ |t| (0..19).to_a.map{ |r| [r, []] }.to_h }
    [type].flatten.each{ |t|
      scores = comparison_(t, tabs, p1, p2)
      (0..4).each{ |i|
        (0..19).each{ |r|
          ret[i][r] += scores[i][r] if !scores[i][r].nil?
        }
      }
    }
    (0..4).each{ |i|
      (0..19).each{ |r|
        ret[i].delete(r) if ret[i][r].empty?
      }
    }
    ret
  end

  def add_alias(a)
    PlayerAlias.find_or_create_by(player: self, alias: a)
  end

  def print_name
    user = User.where(playername: name).where.not(displayname: nil)
    (user.empty? ? name : user.first.displayname).remove("`")
  end

  def format_name(padding = DEFAULT_PADDING)
    format_string(print_name, padding)
  end

  # truncate name
  def tname(length = MAX_PADDING)
    TRUNCATE_NAME ? print_name[0..length] : print_name
  end

  def scores_by_type_and_tabs(type, tabs, include = nil)
    ret = scores.where(highscoreable_type: type.nil? ? DEFAULT_TYPES : type.to_s)
    ret = ret.where(tab: tabs) if !tabs.empty?
    case include
    when :scores
      ret.includes(highscoreable: [:scores])
    when :name
      ret.includes(:highscoreable)
    else
      ret
    end
  end

  def top_ns(n, type, tabs, ties)
    scores_by_type_and_tabs(type, tabs).where("#{ties ? "tied_rank" : "rank"} < #{n}")
  end

  def range_ns(a, b, type, tabs, ties)
    scores_by_type_and_tabs(type, tabs).where("#{ties ? "tied_rank" : "rank"} >= #{a} AND #{ties ? "tied_rank" : "rank"} < #{b}")
  end

  def top_n_count(n, type, tabs, ties)
    top_ns(n, type, tabs, ties).count
  end

  def range_n_count(a, b, type, tabs, ties)
    range_ns(a, b, type, tabs, ties).count
  end

  def scores_by_rank(type, tabs)
    bench(:start) if BENCHMARK
    ret = scores_by_type_and_tabs(type, tabs).group_by(&:rank).sort_by(&:first)
    bench(:step) if BENCHMARK
    ret
  end

  def score_counts(tabs, ties)
    bench(:start) if BENCHMARK
    counts = {
      levels:   scores_by_type_and_tabs(Level,   tabs).group(ties ? :tied_rank : :rank).order(ties ? :tied_rank : :rank).count(:id),
      episodes: scores_by_type_and_tabs(Episode, tabs).group(ties ? :tied_rank : :rank).order(ties ? :tied_rank : :rank).count(:id),
      stories:  scores_by_type_and_tabs(Story,   tabs).group(ties ? :tied_rank : :rank).order(ties ? :tied_rank : :rank).count(:id)
    }
    bench(:step) if BENCHMARK
    counts
  end

  def missing_top_ns(type, tabs, n, ties)
    type = [Level, Episode] if type.nil?
    bench(:start) if BENCHMARK
    scores = [type].flatten.map{ |t|
      ids = top_ns(n, t, tabs, ties).pluck(:highscoreable_id)
      (tabs.empty? ? t : t.where(tab: tabs)).where.not(id: ids).pluck(:name)
    }.flatten
#    scores = (tabs.empty? ? type : type.where(tab: tabs)).where.not(id: ids).pluck(:name)
    bench(:step) if BENCHMARK
    scores
  end

  def improvable_scores(type, tabs, n)
    type = ensure_type(type) # only works for a single type
    bench(:start) if BENCHMARK
    ids = scores_by_type_and_tabs(type, tabs).pluck(:highscoreable_id, :score).to_h
    ret = Score.where(highscoreable_type: type.to_s, highscoreable_id: ids.keys, rank: 0)
    ret = ret.pluck(:highscoreable_id, :score)
             .map{ |id, s| [id, s - ids[id]] }
             .sort_by{ |s| -s[1] }
             .take(n)
             .map{ |id, s| [type.find(id).name, s] }
    bench(:step) if BENCHMARK
    ret
  end

  def points(type, tabs)
    bench(:start) if BENCHMARK
    points = scores_by_type_and_tabs(type, tabs).sum('20 - rank')
    bench(:step) if BENCHMARK
    points
  end

  def average_points(type, tabs)
    bench(:start) if BENCHMARK
    scores = scores_by_type_and_tabs(type, tabs).average('20 - rank')
    bench(:step) if BENCHMARK
    scores
  end

  def total_score(type, tabs)
    bench(:start) if BENCHMARK
    scores = scores_by_type_and_tabs(type, tabs).sum(:score)
    bench(:step) if BENCHMARK
    scores
  end

  def singular_(type, tabs, plural = false)
    req = Score.where(highscoreable_type: type.to_s)
    req = req.where(tab: tabs) if !tabs.empty?
    ids = req.where("rank = 1 AND tied_rank = #{plural ? 0 : 1}").pluck(:highscoreable_id)
    scores_by_type_and_tabs(type, tabs).where(rank: 0, highscoreable_id: ids)
  end

  def singular(type, tabs, plural = false)
    bench(:start) if BENCHMARK
    type = type.nil? ? DEFAULT_TYPES : [type.to_s]
    ret = type.map{ |t| singular_(t, tabs, plural) }.flatten.group_by(&:rank)
    bench(:step) if BENCHMARK
    ret
  end

  def average_lead(type, tabs)
    type = ensure_type(type) # only works for a single type
    bench(:start) if BENCHMARK

    ids = top_ns(1, type, tabs, false).pluck('highscoreable_id')
    ret = Score.where(highscoreable_type: type.to_s, highscoreable_id: ids, rank: [0, 1])
    ret = ret.where(tab: tabs) if !tabs.empty?
    ret = ret.pluck(:highscoreable_id, :score)
    count = ret.count / 2
    return 0 if count == 0
    ret = ret.group_by(&:first).map{ |id, sc| (sc[0][1] - sc[1][1]).abs }.sum / count
## alternative method, faster when the player has many 0ths but slower otherwise (usual outcome)
#    ret = Score.where(highscoreable_type: type.to_s, rank: [0, 1])
#    ret = ret.where(tab: tabs) if !tabs.empty?
#    ret = ret.pluck(:player_id, :highscoreable_id, :score)
#             .group_by{ |s| s[1] }
#             .map{ |h, s| s[0][2] - s[1][2] if s[0][0] == id }
#             .compact
#    count = ret.count
#    return 0 if count == 0
#    ret = ret.sum / count

    bench(:step) if BENCHMARK
    ret
  end

  def table(rank, ties, a, b)
    [Level, Episode, Story].map do |type|
      case rank
      when :rank
        scores.where(highscoreable_type: type)
              .where("#{ties ? "tied_rank" : "rank"} >= #{a} AND #{ties ? "tied_rank" : "rank"} < #{b}")
              .group(:tab)
              .count(:id)
              .to_h
      when :tied_rank
        scores1 = scores.where(highscoreable_type: type)
                        .where("tied_rank >= #{a} AND tied_rank < #{b}")
                        .group(:tab)
                        .count(:id)
                        .to_h
        scores2 = scores.where(highscoreable_type: type)
                        .where("rank >= #{a} AND rank < #{b}")
                        .group(:tab)
                        .count(:id)
                        .to_h
        scores1.map{ |tab, count| [tab, count - scores2[tab]] }.to_h
      when :points
        scores.where(highscoreable_type: type).group(:tab).sum(ties ? "20 - tied_rank" : "20 - rank").to_h
      when :score
        scores.where(highscoreable_type: type).group(:tab).sum(:score).to_h
      when :avg_points
        scores.where(highscoreable_type: type).group(:tab).average(ties ? "20 - tied_rank" : "20 - rank").to_h
      when :avg_rank
        scores.where(highscoreable_type: type).group(:tab).average(ties ? "tied_rank" : "rank").to_h
      when :maxed
        HighScore.ties(type, [], nil, true, false)
                 .select{ |t| t[1] == t[2] }
                 .group_by{ |t| t[0].split("-")[0] }
                 .map{ |tab, scores| [normalize_tab(tab), scores.size] }
                 .to_h
      when :maxable
        HighScore.ties(type, [], nil, false, false)
                 .select{ |t| t[1] < t[2] }  
                 .group_by{ |t| t[0].split("-")[0] }
                 .map{ |tab, scores| [formalize_tab(tab), scores.size] }
                 .to_h   
      else
        scores.where(highscoreable_type: type).group(:tab).count(:id).to_h
      end
    end
  end
end

class LevelAlias < ActiveRecord::Base
  belongs_to :level
end

class PlayerAlias < ActiveRecord::Base
  belongs_to :player
end

class User < ActiveRecord::Base
  def player
    Player.find_by(name: playername)
  end
  def player=(person)
    name = person.class == Player ? person.name : person.to_s
    self.playername = name
    self.save
  end
end

class GlobalProperty < ActiveRecord::Base
end

class RankHistory < ActiveRecord::Base
  belongs_to :player
  enum tab: [:SI, :S, :SU, :SL, :SS, :SS2]

  def self.compose(rankings, type, tab, rank, ties, time)
    rankings.select { |r| r[1] > 0 }.map do |r|
      {
        highscoreable_type: type.to_s,
        rank:               rank,
        ties:               ties,
        tab:                tab,
        player:             r[0],
        count:              r[1],
        metanet_id:         r[0].metanet_id,
        timestamp:          time
      }
    end
  end
end

class PointsHistory < ActiveRecord::Base
  belongs_to :player
  enum tab: [:SI, :S, :SU, :SL, :SS, :SS2]

  def self.compose(rankings, type, tab, time)
    rankings.select { |r| r[1] > 0 }.map do |r|
      {
        timestamp:          time,
        tab:                tab,
        highscoreable_type: type.to_s,
        player:             r[0],
        metanet_id:         r[0].metanet_id,
        points:             r[1]
      }
    end
  end
end

class TotalScoreHistory < ActiveRecord::Base
  belongs_to :player
  enum tab: [:SI, :S, :SU, :SL, :SS, :SS2]

  def self.compose(rankings, type, tab, time)
    rankings.select { |r| r[1] > 0 }.map do |r|
      {
        timestamp:          time,
        tab:                tab,
        highscoreable_type: type.to_s,
        player:             r[0],
        metanet_id:         r[0].metanet_id,
        score:              r[1]
      }
    end
  end
end

class Video < ActiveRecord::Base
  belongs_to :highscoreable, polymorphic: true

  def format_challenge
    return (challenge == "G++" || challenge == "?!") ? challenge : "#{challenge} (#{challenge_code})"
  end

  def format_author
    return "#{author} (#{author_tag})"
  end

  def format_description
    "#{format_challenge} by #{format_author}"
  end
end

class Challenge < ActiveRecord::Base
  belongs_to :level

  def objs
    {
      "G" => self.g,
      "T" => self.t,
      "O" => self.o,
      "C" => self.c,
      "E" => self.e
    }
  end

  def type
    index == 0 ? '!' : '?'
  end

  def count
    objs.select{ |k, v| v != 0 }.count
  end

  def format_type
    "[" + type * count + "]"
  end

  def format_objs
    objs.map{ |k, v|
      v == 1 ? "#{k}++" : (v == -1 ? "#{k}--" : "")
    }.join
  end

  def format(pad)
    format_type + " " * [1, pad - count + 1].max + format_objs
  end
end

class Archive < ActiveRecord::Base
  belongs_to :player
  belongs_to :highscoreable, polymorphic: true
  enum tab: [:SI, :S, :SU, :SL, :SS, :SS2]

  # Returns the leaderboards at a particular point in time
  def self.scores(highscoreable, date)
    self.select('metanet_id', 'max(score)')
        .where(highscoreable: highscoreable)
        .where("unix_timestamp(date) <= #{date}")
        .group('metanet_id')
        .order('max(score) desc, max(replay_id) asc')
        .take(20)
        .map{ |s|
          [s.metanet_id.to_i, s['max(score)'].to_i]
        }
  end

  # Returns the rank of the player at a particular point in time
  def find_rank(time)
    old_score = Archive.scores(self.highscoreable, time)
                       .each_with_index
                       .map{ |s, i| [i, s[0], s[1]] }
                       .select{ |s| s[1] == self.metanet_id }
    old_score.empty? ? 20 : old_score.first[0]
  end

  def format_score
    "%.3f" % self.score.to_f / 60.0
  end

  def demo
    Demo.find(self.id).demo
  end

end

class Demo < ActiveRecord::Base
  #----------------------------------------------------------------------------#
  #                    METANET REPLAY FORMAT DOCUMENTATION                     |
  #----------------------------------------------------------------------------#
  # REPLAY DATA:                                                               |
  #    4B  - Query type                                                        |
  #    4B  - Replay ID                                                         |
  #    4B  - Level ID                                                          |
  #    4B  - User ID                                                           |
  #   Rest - Demo data compressed with zlib                                    |
  #----------------------------------------------------------------------------#
  # LEVEL DEMO DATA FORMAT:                                                    |
  #     1B - Unknown                                                           |
  #     4B - Data length                                                       |
  #     4B - Unknown                                                           |
  #     4B - Frame count                                                       |
  #     4B - Level ID                                                          |
  #    13B - Unknown                                                           |
  #   Rest - Demo                                                              |
  #----------------------------------------------------------------------------#
  # EPISODE DEMO DATA FORMAT:                                                  |
  #     4B - Unknown                                                           |
  #    20B - Block length for each level demo (5 * 4B)                         |
  #   Rest - Demo data (5 consecutive blocks, see above)                       |
  #----------------------------------------------------------------------------#
  # STORY DEMO DATA FORMAT:                                                    |
  #     4B - Unknown                                                           |
  #     4B - Demo data block size                                              |
  #   100B - Block length for each level demo (25 * 4B)                        |
  #   Rest - Demo data (25 consecutive blocks, see above)                      |
  #----------------------------------------------------------------------------#
  # DEMO FORMAT:                                                               |
  #   * One byte per frame.                                                    |
  #   * First bit for jump, second for right and third for left.               |
  #   * Suicide is 12 (0C).                                                    |
  #   * The first frame is fictional and must be ignored.                      |
  #----------------------------------------------------------------------------#
  enum htype: [:level, :episode, :story]

  def score
    Archive.find(self.id)
  end

  def qt
    case htype.to_sym
    when :level
      0
    when :episode
      1
    when :story
      4
    else
      -1 # error checking
    end
  end

  def demo_uri(steam_id)
    URI.parse("https://dojo.nplusplus.ninja/prod/steam/get_replay?steam_id=#{steam_id}&steam_auth=&replay_id=#{replay_id}&qt=#{qt}")
  end

  def get_demo
    attempts ||= 0
    initial_id = get_last_steam_id
    response = Net::HTTP.get_response(demo_uri(initial_id))
    while response.body == INVALID_RESP
      deactivate_last_steam_id
      update_last_steam_id
      break if get_last_steam_id == initial_id
      response = Net::HTTP.get_response(demo_uri(get_last_steam_id))
    end
    return 1 if response.code.to_i == 200 && response.body.empty? # replay does not exist
    return nil if response.body == INVALID_RESP
    raise "502 Bad Gateway" if response.code.to_i == 502
    activate_last_steam_id
    response.body
  rescue => e
    if (attempts += 1) < RETRIES
      if SHOW_ERRORS
        err("error getting demo with id #{replay_id}: #{e}")
      end
      retry
    else
      return nil
    end
  end

  def parse_demo(replay)
    data   = Zlib::Inflate.inflate(replay[16..-1])
    header = {level: 0, episode:  4, story:   8}[htype.to_sym]
    offset = {level: 0, episode: 24, story: 108}[htype.to_sym]
    count  = {level: 1, episode:  5, story:  25}[htype.to_sym]

    lengths = (0..count - 1).map{ |d| _unpack(data[header + 4 * d..header + 4 * (d + 1) - 1]) }
    lengths = [_unpack(data[1..4])] if htype.to_sym == :level
    (0..count - 1).map{ |d|
      offset += lengths[d - 1] unless d == 0
      data[offset..offset + lengths[d] - 1][30..-1]
    }
  end

  def encode_demo(replay)
    replay = [replay] if replay.class == String
    Zlib::Deflate.deflate(replay.join('&'), 9)
  end

  def decode_demo
    return nil if demo.nil?
    demos = Zlib::Inflate.inflate(demo).split('&')
    return (demos.size == 1 ? demos.first.scan(/./m).map(&:ord) : demos.map{ |d| d.scan(/./m).map(&:ord) })
  end

  def update_demo
    replay = get_demo
    return nil if replay.nil? # replay was not fetched successfully
    if replay == 1 # replay does not exist
      ActiveRecord::Base.transaction do
        self.update(expired: true)
      end
      return nil
    end
    ActiveRecord::Base.transaction do
      self.update(
        demo: encode_demo(parse_demo(replay)),
        expired: false
      )
    end
  rescue => e
    if SHOW_ERRORS
      err("error parsing demo with id #{replay_id}: #{e}")
    end
    return nil
  end
end

module Twitch extend self

  GAME_IDS = {
#    'N'     => 12273, # Commented because it's usually non-N related :(
    'N+'    => 18983,
    'Nv2'   => 105456,
    'N++'   => 369385
#    'GTASA' => 6521 # This is for testing purposes, since often there are no N streams live
  }

  def get_twitch_token
    GlobalProperty.find_by(key: 'twitch_token').value
  end

  def set_twitch_token(token)
    GlobalProperty.find_by(key: 'twitch_token').update(value: token)
  end

  def table_header
    "#{"Player".ljust(15, " ")} #{"Title".ljust(35, " ")} #{"Time".ljust(12, " ")} #{"Views".ljust(4, " ")}\n#{"-" * 70}"
  end

  def format_stream(s)
    name  = to_ascii(s['user_name'].remove("\n").strip[0..14]).ljust(15, ' ')
    title = to_ascii(s['title'].remove("\n").strip[0..34]).ljust(35, ' ')
    time  = "#{(Time.now - DateTime.parse(s['started_at']).to_time).to_i / 60} mins ago".rjust(12, ' ')
    views = s['viewer_count'].to_s.rjust(5, ' ')
    "#{name} #{title} #{time} #{views}"
  end

  def update_twitch_token
    res = Net::HTTP.post_form(
      URI.parse("https://id.twitch.tv/oauth2/token"),
      {
        client_id: $config['twitch_id'],
        client_secret: ENV['TWITCH_SECRET'],
        grant_type: 'client_credentials'
      }
    )
    if res.code.to_i == 401
      err("TWITCH: Unauthorized to perform requests, please verify you have this correctly configured.")      
    elsif res.code.to_i != 200
      err("TWITCH: App access token request failed.")
    else
      $twitch_token = JSON.parse(res.body)['access_token']
      set_twitch_token($twitch_token)
    end
  rescue
    err("TWITCH: App access token request method failed.")
    sleep(5)
    retry
  end

  # TODO: Add attempts to the loop, raise if fail
  def get_twitch_game_id(name)
    update_twitch_token if $twitch_token.nil?
    uri = URI("https://api.twitch.tv/helix/games?name=#{name}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    loop do
      res = http.get(
        uri.request_uri,
        {
          'Authorization' => "Bearer #{$twitch_token}",
          'Client-Id' => $config['twitch_id']
        }
      )
      if res.code.to_i == 401
        update_twitch_token
        sleep(5)
      elsif res.code.to_i != 200
        err("TWITCH: Game ID request failed.")
        sleep(5)
      else
        return JSON.parse(res.body)['id'].to_i
      end
    end
  rescue
    err("TWITCH: Game ID request method failed.")
    sleep(5)
    retry
  end

 # TODO: Add attempts to the loops, raise if fail
 # TODO: Add offset/pagination for when there are many results
  def get_twitch_streams(name, offset = nil)
    if !GAME_IDS.key?(name)
      err("TWITCH: Supplied game not known.")
      return
    end
    while $twitch_token.nil?
      update_twitch_token
      sleep(5)
    end
    uri = URI("https://api.twitch.tv/helix/streams?first=100&game_id=#{GAME_IDS[name]}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    res = nil
    loop do
      res = http.get(
        uri.request_uri,
        {
          'Authorization' => "Bearer #{$twitch_token}",
          'Client-Id' => $config['twitch_id']
        }
      )
      if res.code.to_i == 401
        update_twitch_token
        sleep(5)
      elsif res.code.to_i != 200
        err("TWITCH: Stream list request for #{name} failed.")
        sleep(5)
      else
        break
      end
    end
    JSON.parse(res.body)['data'].sort_by{ |s| s['user_name'].downcase }
  rescue
    err("TWITCH: Stream list request method for #{name} failed.")
    sleep(5)
    retry
  end

  def update_twitch_streams
    GAME_IDS.each{ |game, id|
      $twitch_streams[game] = get_twitch_streams(game)
    }
  end

end
