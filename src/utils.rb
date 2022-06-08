# Library of general functions useful throughout the program

require_relative 'constants.rb'
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