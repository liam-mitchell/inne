require_relative 'constants.rb'
require_relative 'utils.rb'
require_relative 'messages.rb'
require_relative 'userlevels.rb'

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

# ActionRow builder with a Select Menu for the highscoreable type
# (All, Level, Episode, Story)
def interaction_add_select_menu_type(view, type = nil)
  type = 'overall' if type.nil? || type.empty?
  view = Discordrb::Webhooks::View.new if view.nil?
  view.row{ |r|
    r.select_menu(custom_id: 'menu:type', placeholder: 'Type', max_values: 1){ |m|
      ['overall', 'level', 'episode', 'story'].each{ |b|
        label = b == 'overall' ? 'Levels + Episodes' : b.capitalize.pluralize
        m.option(label: "Type: #{label}", value: "menu:type:#{b}", default: b == type)
      }
    }
  }
ensure
  view
end

# ActionRow builder with a Select menu for the highscorable tabs
# (All, SI, S, SU, SL, SS, SS2)
def interaction_add_select_menu_metanet_tab(view, tab = nil)
  view = Discordrb::Webhooks::View.new if view.nil?
  view.row{ |r|
    r.select_menu(custom_id: 'menu:tab', placeholder: 'Tab', max_values: 1){ |m|
      ['all', 'si', 's', 'su', 'sl', 'ss', 'ss2'].each{ |t|
        m.option(
          label:   t == 'all' ? 'All tabs' : format_tab(t.upcase.to_sym) + ' tab',
          value:   "menu:tab:#{t}",
          default: t == tab
        )
      }
    }
  }
ensure
  view
end

# ActionRow builder with a Select menu for the ranking types
# (0th, Top5, Top10, Top20, Average rank,
# 0th (w/ ties), Tied 0ths, Singular 0ths, Plural 0ths, Average 0th lead
# Maxed, Maxable, Score, Points, Average points)
def interaction_add_select_menu_rtype(view, rtype = nil)
  view = Discordrb::Webhooks::View.new if view.nil?
  view.row{ |r|
    r.select_menu(custom_id: 'menu:rtype', placeholder: 'Ranking type', max_values: 1){ |m|
      RTYPES.each{ |t|
        m.option(
          label:   "#{format_rtype(t).titleize}",
          value:   "menu:rtype:#{t}",
          default: t == rtype
        )
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

# Template ActionRow builder with Buttons for navigation
def interaction_add_navigation(view, labels: [], disabled: [], ids: [])
  view = Discordrb::Webhooks::View.new if view.nil?
  view.row{ |r|
    r.button(label: labels[0], style: :primary,   disabled: disabled[0], custom_id: ids[0])
    r.button(label: labels[1], style: :primary,   disabled: disabled[1], custom_id: ids[1])
    r.button(label: labels[2], style: :secondary, disabled: disabled[2], custom_id: ids[2])
    r.button(label: labels[3], style: :primary,   disabled: disabled[3], custom_id: ids[3])
    r.button(label: labels[4], style: :primary,   disabled: disabled[4], custom_id: ids[4])
  }
ensure
  view
end

# ActionRow builder with Buttons for standard page navigation
def interaction_add_button_navigation(view, page = 1, pages = 1, offset = 1000000000)
  interaction_add_navigation(
    view,
    labels: ["❙❮", "❮", "#{page} / #{pages}", "❯", "❯❙"],
    disabled: [page == 1, page == 1, true, page == pages, page == pages],
    ids: ["button:nav:#{-offset}", "button:nav:-1", "button:nav:page", "button:nav:1", "button:nav:#{offset}"]
  )
end

# ActionRow builder with Buttons for level/episode/story navigation
def interaction_add_level_navigation(view, name)
  interaction_add_navigation(
    view,
    labels: ["❮❮", "❮", name, "❯", "❯❯"],
    disabled: [false, false, true, false, false],
    ids: ["button:id:-2", "button:id:-1", "button:id:page", "button:id:1", "button:id:2"]
  )
end

# ActionRow builder with Buttons for date navigation
def interaction_add_date_navigation(view, page = 1, pages = 1, date = 0, label = "")
  interaction_add_navigation(
    view,
    labels: ["❙❮", "❮", label, "❯", "❯❙"],
    disabled: [page == 1, page == 1, true, page == pages, page == pages],
    ids: ["button:date:-1000000000", "button:date:-1", "button:date:#{date}", "button:date:1", "button:date:1000000000"]
  )
end

# ActionRow builder with Buttons to specify type (Level, Episode, Story)
# in Rankings, also button to include ties.
def interaction_add_type_buttons(view, types = [], ties = nil)
  view = Discordrb::Webhooks::View.new if view.nil?
  view.row{ |r|
    TYPES.each{ |t, h|
      r.button(
        label: h[:name].capitalize.pluralize,
        style: types.include?(h[:name].capitalize.constantize) ? :success : :danger,
        custom_id: "button:type:#{h[:name].downcase}"
      )
    }
    r.button(label: 'Ties', style: ties ? :success : :danger, custom_id: "button:ties:#{!ties}")
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
def send_message_with_interactions(event, msg, view = nil, edit = false, attachments = [])
  if edit # ButtonEvent / SelectMenuEvent
    event.update_message(content: msg, components: view)
  else # MentionEvent / PrivateMessageEvent
    event.channel.send_message(msg, false, nil, attachments, nil, nil, view)
  end
end

def craft_userlevel_browse_msg(event, msg, page: 1, pages: 1, order: nil, tab: nil, mode: nil, edit: false, int: true)
  # Normalize pars
  order = "default" if order.nil? || order.empty?
  order = order.downcase.split(" ").first
  order = "date" if order == "id"
  tab = "all" if !USERLEVEL_TABS.map{ |t, v| v[:name] }.include?(tab)
  mode = "solo" if !MODES.values.include?(mode.to_s.downcase)
  # Create and fill component collection (View)
  view = Discordrb::Webhooks::View.new
  if int
    interaction_add_button_navigation(view, page, pages) unless pages == 1
    interaction_add_select_menu_order(view, order)
    interaction_add_select_menu_tab(view, tab)
    interaction_add_select_menu_mode(view, mode)
  end
  # Send
  send_message_with_interactions(event, msg, view, edit)
end

# Important notes for parsing interaction components:
#
# 1) We determine the origin of the interaction (the bot's source message) based
#    on the first word of the message. Therefore, we have to format this first
#    word (and, often, the first sentence) properly so that the bot can parse it.
#
# 2) We use the custom_id of the component (button, select menu) and of the
#    component option (select menu option) to classify them and determine what
#    they do. Therefore, they must ALL follow a specific pattern:
#
#    IDs will be strings composed by a series of keywords separated by colons:
#      The first keyword specifies the type of component (button, menu).
#      The second keyword specifies the category of the component (up to you).
#      The third keyword specifies the specific component (button, select menu option).
def respond_interaction_button(event)
  keys   = event.custom_id.to_s.split(':')                       # Component parameters
  type   = event.message.content.strip.split(' ').first.downcase # Source message type
  return if keys[0] != 'button' # Only listen to components of type "Button"

  case type
  when 'browsing'
    case keys[1]
    when 'nav'
      send_userlevel_browse(event, page: keys[2])
    end
  when 'aliases'
    case keys[1]
    when 'nav'
      send_aliases(event, page: keys[2])
    end
  when 'navigating'
    case keys[1]
    when 'id'
      send_nav_scores(event, offset: keys[2])
    when 'date'
      send_nav_scores(event, date: keys[2])
    end
  when 'search'
    case keys[1]
    when 'nav'
      send_query(event, page: keys[2])
    end
  when 'rankings'
    case keys[1]
    when 'nav'
      send_rankings(event, page: keys[2])
    when 'ties'
      send_rankings(event, ties: keys[2] == 'true')
    when 'type'
      send_rankings(event, type: keys[2])
    end
  end
end

def respond_interaction_menu(event)
  keys   = event.custom_id.to_s.split(':')                       # Component parameters
  values = event.values.map{ |v| v.split(':') }                  # Component option parameters
  type   = event.message.content.strip.split(' ').first.downcase # Source message type
  return if keys[0] != 'menu' # Only listen to components of type "Select Menu"
  
  case type
  when 'browsing' # Select Menus for the userlevel browse function
    case keys[1]
    when 'order' # Reorder userlevels (by title, author, date, favs)
      send_userlevel_browse(event, order: values.first.last)
    when 'tab' # Change tab (all, best, featured, top, hardest)
      send_userlevel_browse(event, tab: values.first.last)
    when 'mode' # Change mode (all, solo, coop, race)
      send_userlevel_browse(event, mode: values.first.last)
    end
  when 'aliases' # Select Menus for the alias list function
    case keys[1]
    when 'alias' # Change type of alias (level, player)
      send_aliases(event, type: values.first.last)
    end
  when 'rankings'# Select Menus for the rankings function
    case keys[1]
    when 'rtype' # Change rankings type (0th rankings, top20 rankings, etc)
      send_rankings(event, rtype: values.first.last)
    when 'tab' # Change highscoreable tab (all, si, s, su, sl, ss, ss2)
      send_rankings(event, tab: values.first.last)
    end
  end
end
