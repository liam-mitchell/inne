# IMPORTANT NOTE: To set up the bot for the first time:
#
# 1) Set up the following environment variable:
# 1.1) DISCORD_TOKEN - This is Discord's application token / secret for your bot.
# 2) Set up the following 2 environment variables (optional):
# 2.1) TWITCH_SECRET - This is your Twitch app's secret, if you want to be able to
#                      use the Twitch functionality. Otherwise, disable the
#                      variable UPDATE_TWITCH in constants.rb.
# 2.2) DISCORD_TOKEN_TEST - Same as DISCORD_TOKEN, but for a secondary development
#                           bot. If you don't care about this, never enable the
#                           variable TEST in constants.rb.
# 3)  Configure the "outte" environment of the config file in ./db/config.yml,
#     or create a new one and rename the DATABASE variable in constants.rb.
# 4)  Configure the "outte_test" environment of the config file (optional).
# 5)  Create, migrate and seed a database named "inne". Make sure to use MySQL 5.7
#     with utf8mb4 encoding and collation. Alternatively, contact whoever is taking
#     care of the bot for a copy of the database (see Contact).
# 6)  Install Ruby 2.6 to maximize compatibility, then run the Bundler to
#     obtain the correct version of all gems (libraries), I recommend using rbenv.
#     In particular, ensure you have Rails 5.1.x and Discordrb >= 3.4.2.
# 7)  Make sure you edit and save the source files in UTF8.
# 8)  You might want to look into 'constants.rb' and configure some variables,
#     in particular, the BOTMASTER_ID, SERVER_ID or CHANNEL_ID. For testing,
#     also look into TEST, DO_NOTHING, and DO_EVERYTHING.
# 9)  You need Python 3 for the tracing capabilities. If you want to disable them,
#     toggle FEATURE_NTRACE to false.
# 10) Make sure the working directory is the bot's root directory when you run it.
#
# Contact: Eddy @ https://discord.gg/nplusplus

# We use some gems directly from Github repositories (in particular, Discordrb,
# so that we can use the latest features, not present in the outdated RubyGems
# version). This is supported by Bundler but not by RubyGems directly. The next
# two lines makes these gems available / visible.
require 'rubygems'
require 'bundler/setup'

# Gems useful throughout the entire program
# (each source file might contain further specific gems)
require 'byebug'
require 'discordrb'
require 'fileutils'
require 'json'
require 'memory_profiler'
require 'net/http'
require 'time'
require 'yaml'
require 'zlib'

# Import all other source files
# (each source file still imports all the ones it needs, to keep track)
require_relative 'constants.rb'
require_relative 'utils.rb'
require_relative 'io.rb'
require_relative 'interactions.rb'
require_relative 'models.rb'
require_relative 'messages.rb'
require_relative 'userlevels.rb'
require_relative 'mappacks.rb'
require_relative 'threads.rb'

# TODO: Use log_exception for all exceptions in all files

def monkey_patch
  MonkeyPatches.apply
  log("Applied monkey patches")
rescue => e
  fatal("Failed to apply monkey patches: #{e}")
  exit
end

def initialize_vars
  $config          = nil
  $channel         = nil
  $mapping_channel = nil
  $nv2_channel     = nil
  $content_channel = nil
  $last_potato     = Time.now.to_i
  $potato          = 0
  $last_mishu      = nil
  $status_update   = Time.now.to_i
  $twitch_token    = nil
  $twitch_streams  = {}
  $boot_time       = Time.now.to_i
  $mutex           = { ntrace: Mutex.new }
  [DIR_LOGS].each{ |d| Dir.mkdir(d) unless Dir.exist?(d) }
  log("Initialized global variables")
rescue => e
  fatal("Failed to initialize global variables: #{e}")
  exit
end

def load_config
  $config = YAML.load_file(CONFIG)[DATABASE]
  $config['discord_client'] = (TEST ? ENV['DISCORD_CLIENT_TEST'] : ENV['DISCORD_CLIENT']).to_i
  $config['discord_secret'] =  TEST ? ENV['DISCORD_TOKEN_TEST']  : ENV['DISCORD_TOKEN']
  $config['twitch_client']  = ENV['TWITCH_CLIENT']
  $config['twitch_secret']  = ENV['TWITCH_SECRET']
  log("Loaded config")
rescue => e
  fatal("Failed to load config: #{e}")
  exit
end

def connect_db
  ActiveRecord::Base.establish_connection($config)
  log("Connected to database")
rescue => e
  fatal("Failed to connect to the database: #{e}")
  exit
end

def disconnect_db
  ActiveRecord::Base.connection_handler.clear_active_connections!
  ActiveRecord::Base.connection.disconnect!
  ActiveRecord::Base.connection.close
  log("Disconnected from database")
rescue => e
  fatal("Failed to disconnect from the database: #{e}")
  exit
end

def create_bot
  $bot = Discordrb::Bot.new(
    token:     $config['discord_secret'],
    client_id: $config['discord_client'],
    log_mode:  :quiet,
    intents:   [
      :servers,
      :server_members,
      :server_bans,
      :server_emojis,
      :server_integrations,
      :server_webhooks,
      :server_invites,
      :server_voice_states,
      #:server_presences,
      :server_messages,
      :server_message_reactions,
      :server_message_typing,
      :direct_messages,
      :direct_message_reactions,
      :direct_message_typing
    ]
  )
  log("Created bot")
rescue => e
  fatal("Failed to create bot: #{e}")
  exit
end

def setup_bot
  $bot.private_message do |event|
    next if !RESPOND && event.user.id != BOTMASTER_ID
    remove_mentions!(event.content)
    special = event.user.id == BOTMASTER_ID && event.content[0] == '!'
    special ? respond_special(event) : respond(event)
    str = special ? 'Special ' : ''
    str = "#{str}DM by #{event.user.name}: #{event.content}"
    special ? succ(str) : msg(str)
  end

  $bot.mention do |event|
    next if !RESPOND && event.user.id != BOTMASTER_ID
    remove_mentions!(event.content)
    respond(event)
    msg("Mention by #{event.user.name} in #{event.channel.name}: #{event.content}")
  end

  $bot.message do |event|
    next if !RESPOND && event.user.id != BOTMASTER_ID
    remove_mentions!(event.content)
    if event.channel == $nv2_channel
      $last_potato = Time.now.to_i
      $potato = 0
    end
    mishnub(event) if MISHU && event.content.downcase.include?("mishu")
    robot(event) if !!event.content[/eddy\s*is\s*a\s*robot/i]
    if event.content[0] == '!' && event.user.id == BOTMASTER_ID && event.channel.type != 1
      respond_special(event)
      succ("Special command: #{event.content}")
    end
  end

  $bot.button do |event|
    next if !RESPOND && event.user.id != BOTMASTER_ID
    respond_interaction_button(event)
  end

  $bot.select_menu do |event|
    next if !RESPOND && event.user.id != BOTMASTER_ID
    respond_interaction_menu(event)
  end
  log("Configured bot")
rescue => e
  fatal("Failed to configure bot: #{e}")
  exit
end

def run_bot
  $bot.run(true)
  trap("INT") { shutdown }
  leave_unknown_servers
  log("Bot connected to servers: #{$bot.servers.map{ |id, s| s.name }.join(', ')}.")
rescue => e
  fatal("Failed to execute bot: #{e}")
  exit
end

def stop_bot
  $bot.stop
  log("Stopped bot")
rescue => e
  fatal("Failed to stop the bot: #{e}")
  exit
end

def shutdown
  log("Shutting down...")
  # We need to perform the shutdown in a new thread, because this method
  # gets called from within a trap context
  Thread.new {
    Sock.off
    stop_bot
    disconnect_db
    unblock_threads
    exit
  }
rescue => e
  fatal("Failed to shut down bot: #{e}")
  exit
end

# Bot initialization sequence
log("Loading outte...")
monkey_patch
initialize_vars
load_config
connect_db
create_bot
setup_bot
run_bot
set_channels
start_threads
byebug if BYEBUG
block_threads