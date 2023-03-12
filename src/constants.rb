# <--------------------------------------------------------------------------->
# <------                   DEVELOPMENT VARIABLES                       ------>
# <--------------------------------------------------------------------------->

TEST           = true  # Switch to the local test bot
TEST_REPORT    = false # Produces the report immediately once
SHOW_ERRORS    = true  # Log common error messages to the console
LOG_SQL        = false # Log _all_ SQL queries to the console (for debugging)
LOG            = false # Export logs and errors into external file
LOG_REPORT     = false # Log new weekly scores that appear in the report
DO_NOTHING     = false # Don't execute any threads (see below for ind flags)
DO_EVERYTHING  = false # Execute all threads
RESPOND        = true  # Respond to pings / DMs (for testing)
BYEBUG         = false # Breakpoint right after loading the bot

# <--------------------------------------------------------------------------->
# <------                     INTERNAL VARIABLES                        ------>
# <--------------------------------------------------------------------------->

WAIT           = 1     # Seconds to wait between each iteration of the infinite while loops to prevent craziness
BENCHMARK      = false # Benchmark and log functions (for optimization)
BENCH_MSGS     = false # Benchmark functions _in messages_
DATABASE_ENV   = ENV['DATABASE_ENV'] || (TEST ? 'outte_test' : 'outte')
CONFIG         = YAML.load_file('db/config.yml')[DATABASE_ENV]

# <--------------------------------------------------------------------------->
# <------                     NETWORK VARIABLES                         ------>
# <--------------------------------------------------------------------------->

RETRIES        = 50      # Redownload attempts for boards / demos
ATTEMPT_LIMIT  = 5       # Redownload attempts in general (bigger files)
INVALID_RESP   = '-1337' # N++'s server response when Steam ID is inactive
DEFAULT_TYPES  = ['Level', 'Episode'] # Default highscoreable types

# <--------------------------------------------------------------------------->
# <------                     DISCORD VARIABLES                         ------>
# <--------------------------------------------------------------------------->

BOTMASTER_ID   = 204332624288677890 # User ID of the bot manager (Eddy)
SERVER_ID      = 197765375503368192 # Discord server/guild ID (N++ Server)
CHANNEL_ID     = 210778111594332181 # Discord main channel ID (#highscores)
USERLEVELS_ID  = 221721273405800458 # ... (#mapping)
NV2_ID         = 197774025844457472 # ... (#nv2)
CONTENT_ID     = 197793786389200896 # ... (#content-creation)
DISCORD_LIMIT  = 2000               # Message character limit

# <--------------------------------------------------------------------------->
# <------                       FORMAT VARIABLES                        ------>
# <--------------------------------------------------------------------------->

# Input
LEVEL_PATTERN     = /S[ILU]?-[ABCDEX]-[0-9][0-9]?-[0-9][0-9]?|[?!]-[ABCDEX]-[0-9][0-9]?/i
LEVEL_PATTERN_D   = /(S[ILU]?)-?([ABCDEX])-?([0-9][0-9]?)-?([0-9][0-9]?)|([?!])-?([ABCDEX])-?([0-9][0-9]?)/i
EPISODE_PATTERN   = /S[ILU]?-[ABCDEX]-[0-9][0-9]?/i
EPISODE_PATTERN_D = /(S[ILU]?)-?([ABCDEX])-?([0-9][0-9]?)/i
STORY_PATTERN     = /(S[ILU]?)-?([0-9][0-9]?)/i
NAME_PATTERN      = /(for|of) (.*)[\.\?]?/i
MAX_ENTRIES       = 20 # maximum number of entries on methods with user input, to avoid spam

# Output
NUM_ENTRIES     = 20   # number of entries to show on most methods
SCORE_PADDING   =  0   #         fixed    padding, 0 for no fixed padding
DEFAULT_PADDING = 15   # default variable padding, never make 0
MAX_PADDING     = 15   # max     variable padding, 0 for no maximum
MAX_PAD_GEN     = 80   # max padding for general strings (not player names)
TRUNCATE_NAME   = true # truncate name when it exceeds the maximum padding

# Dates
DATE_FORMAT_NPP   = "%Y-%m-%d-%H:%M"    # Date format used by N++
DATE_FORMAT_OUTTE = "%Y/%m/%d %H:%M"    # Date format used by outte
DATE_FORMAT_MYSQL = "%Y-%m-%d %H:%M:%S" # Date format required by MySQL

# <--------------------------------------------------------------------------->
# <------                   USERLEVEL VARIABLES                         ------>
# <--------------------------------------------------------------------------->

MIN_U_SCORES = 20    # Minimum number of userlevel highscores to appear in average rankings
MIN_G_SCORES = 500   # Minimum number of userlevel highscores to appear in global average rankings
PAGE_SIZE    = 10    # Number of userlevels to show when browsing
PART_SIZE    = 500   # Number of userlevels per file returned by the server when querying levels
MIN_ID       = 22715 # ID of the very first userlevel, to exclude Metanet levels
#   Mapping of the qt (query type) to each userlevel tab.
#     'name'     - Internal name used to identify each tab.
#     'fullname' - Display name of tab 
#     'update'   - Determines whether we update our db's tab info.
#     'size'     - Determines how many maps from each tab to update.
USERLEVEL_TABS = {
  10 => { name: 'all',      fullname: 'All',        size: -1,   update: false }, # keep first
  7  => { name: 'best',     fullname: 'Best',       size: 1000, update: true  },
  8  => { name: 'featured', fullname: 'Featured',   size: -1,   update: true  },
  9  => { name: 'top',      fullname: 'Top Weekly', size: 1000, update: true  },
  11 => { name: 'hardest',  fullname: 'Hardest',    size: 1000, update: true  }
}
USERLEVEL_REPORT_SIZE = 500 # Number of userlevels to include in daily rankings
INVALID_NAMES = [nil, "null", ""] # Names that correspond to invalid players

# <--------------------------------------------------------------------------->
# <------                       JOKE VARIABLES                          ------>
# <--------------------------------------------------------------------------->

POTATO         = true               # joke they have in the nv2 channel
POTATO_RATE    = 1                  # seconds between potato checks
POTATO_FREQ    = 3 * 60 * 60        # 3 hours between potato delivers
FRUITS         = [':potato:', ':tomato:', ':eggplant:', ':peach:', ':carrot:', ':pineapple:', ':cucumber:', ':cheese:']
MISHU          = true               # MishNUB joke
MISHU_COOLDOWN = 30 * 60            # MishNUB cooldown
COOL           = true               # Emoji for CKC in leaderboards

# <--------------------------------------------------------------------------->
# <------                       TASK VARIABLES                          ------>
# <--------------------------------------------------------------------------->

# Individual flags for each thread / task
OFFLINE_MODE      = false # Disables most intensive online functionalities
OFFLINE_STRICT    = false # Disables all online functionalities of outte
UPDATE_STATUS     = false # Thread to regularly update the bot's status
UPDATE_TWITCH     = false # Thread to regularly look up N related Twitch streams
UPDATE_SCORES     = false # Thread to regularly download Metanet's scores
UPDATE_HISTORY    = false # Thread to regularly update highscoring histories
UPDATE_DEMOS      = false # Thread to regularly download missing Metanet demos
UPDATE_LEVEL      = false # Thread to regularly publish level of the day
UPDATE_EPISODE    = false # Thread to regularly publish episode of the week
UPDATE_STORY      = false # Thread to regularly publish column of the month
UPDATE_USERLEVELS = false # Thread to regularly download newest userlevel scores
UPDATE_USER_GLOB  = false # Thread to continuously (but slowly) download all userlevel scores
UPDATE_USER_HIST  = false # Thread to regularly update userlevel highscoring histories
UPDATE_USER_TABS  = false # Thread to regularly update userlevel tabs (best, featured, top, hardest)
REPORT_METANET    = false # Thread to regularly post Metanet's highscoring report
REPORT_USERLEVELS = false # Thread to regularly post userlevels' highscoring report

# Update frequencies for each task
STATUS_UPDATE_FREQUENCY     = CONFIG['status_update_frequency']     ||            5 * 60 # every 5 mins
TWITCH_UPDATE_FREQUENCY     = CONFIG['twitch_update_frequency']     ||                60 # every 1 min
HIGHSCORE_UPDATE_FREQUENCY  = CONFIG['highscore_update_frequency']  ||      24 * 60 * 60 # daily
HISTORY_UPDATE_FREQUENCY    = CONFIG['history_update_frequency']    ||      24 * 60 * 60 # daily
DEMO_UPDATE_FREQUENCY       = CONFIG['demo_update_frequency']       ||      24 * 60 * 60 # daily
LEVEL_UPDATE_FREQUENCY      = CONFIG['level_update_frequency']      ||      24 * 60 * 60 # daily
EPISODE_UPDATE_FREQUENCY    = CONFIG['episode_update_frequency']    ||  7 * 24 * 60 * 60 # weekly
STORY_UPDATE_FREQUENCY      = CONFIG['story_update_frequency']      || 30 * 24 * 60 * 60 # monthly (roughly)
REPORT_UPDATE_FREQUENCY     = CONFIG['report_update_frequency']     ||      24 * 60 * 60 # daily
REPORT_UPDATE_SIZE          = CONFIG['report_update_size']          ||  7 * 24 * 60 * 60 # last 7 days
SUMMARY_UPDATE_SIZE         = CONFIG['summary_update_size']         ||  1 * 24 * 60 * 60 # last day
USERLEVEL_SCORE_FREQUENCY   = CONFIG['userlevel_score_frequency']   ||      24 * 60 * 60 # daily
USERLEVEL_UPDATE_RATE       = CONFIG['userlevel_update_rate']       ||                15 # every 5 secs
USERLEVEL_HISTORY_FREQUENCY = CONFIG['userlevel_history_frequency'] ||      24 * 60 * 60 # daily
USERLEVEL_REPORT_FREQUENCY  = CONFIG['userlevel_report_frequency']  ||      24 * 60 * 60 # daily
USERLEVEL_TAB_FREQUENCY     = CONFIG['userlevel_tab_frequency']     ||      24 * 60 * 60 # daily
USERLEVEL_DOWNLOAD_CHUNK    = CONFIG['userlevel_download_chunk']    ||               100 # 100 maps at a time

# <--------------------------------------------------------------------------->
# <------                      TWITCH VARIABLES                         ------>
# <--------------------------------------------------------------------------->

TWITCH_ROLE      = "Voyeur"    # Discord role to ping when a new stream happens
TWITCH_COOLDOWN  = 2 * 60 * 60 # Cooldown to ping stream by the same user
TWITCH_BLACKLIST = [
  "eblan4ikof"
]

# <--------------------------------------------------------------------------->
# <------                      SOCKET VARIABLES                         ------>
# <--------------------------------------------------------------------------->

# Variables that control the TCP socket we open to listen to the N++ Search
# Engine, a tool that uses outte's database to perform custom userlevel queries
# and inject them directly in-game.

SOCKET           = true # Whether to open socket or not
SOCKET_PORT      = 8125 # Port to listen to
QUERY_LIMIT_SOFT = 25   # Number of queried userlevels per page
QUERY_LIMIT_HARD = 500  # Maximum number of queried userlevels per page

# <--------------------------------------------------------------------------->
# <------                 HIGHSCORING VARIABLES                         ------>
# <--------------------------------------------------------------------------->

MIN_TIES = 3 # Minimum number of ties for 0th to be considered maxable
MAX_SECS = 5 # Difference in seconds to consider two dates equal (for navigation)

# @par1: ID ranges for levels and episodes
# @par2: Score limits to filter new hacked scores
# @par3: Number of scores required to enter the average rank/point rankings of tab
TABS = {
  "Episode" => {
    :SI => [ (  0.. 24).to_a, 400,  5],
    :S  => [ (120..239).to_a, 950, 25],
    :SL => [ (240..359).to_a, 650, 25],
    :SU => [ (480..599).to_a, 650, 25]
  },
  "Level" => {
    :SI  => [ (  0..  124).to_a,  298, 25],
    :S   => [ ( 600..1199).to_a,  874, 50],
    :SL  => [ (1200..1799).to_a,  400, 50],
    :SS  => [ (1800..1919).to_a, 2462, 25],
    :SU  => [ (2400..2999).to_a,  530, 50],
    :SS2 => [ (3000..3119).to_a,  322, 25]
  },
  "Story" => {
    :SI => [ ( 0..  4).to_a, 1000, 1],
    :S  => [ (24.. 43).to_a, 2000, 5],
    :SL => [ (48.. 67).to_a, 2000, 5],
    :SU => [ (96..115).to_a, 1500, 5]
  }
}

# Different ranking types
# * For parsing, 'top1' (i.e. 0th) will be removed (default)
# * For formatting, 'top1' will be changed to '0th'
RTYPES = [
  'top1',
  'top5',
  'top10',
  'top20',
  'average_rank',
  'cool',
  'star',
  'tied_top1',
  'singular_top1',
  'plural_top1',
  'average_top1_lead',
  'maxed',
  'maxable',
  'score',
  'point',
  'average_point'
]

MODES = {
  -1 => "all",
   0 => "solo",
   1 => "coop",
   2 => "race"
}

# Type-wise max-min for average ranks
MAXMIN_SCORES = 100   # max-min number of highscores to appear in average point rankings
TYPES = {
  "Level"   => [100],
  "Episode" =>  [50],
  "Story"   =>  [10]
}

IGNORED_PLAYERS = [
  "Kronogenics",
  "BlueIsTrue",
  "fiordhraoi",
  "cheeseburgur101",
  "Jey",
  "jungletek",
  "Hedgy",
  "ᕈᘎᑕᒎᗩn ᙡiᗴᒪḰi",
  "Venom",
  "EpicGamer10075",
  "Altii",
  "Pu𝐜ͥⷮⷮⷮⷮͥⷮͥⷮe",
  "Floof The Goof",
  "Prismo",
  "Mishu",
  "dimitry008",
  "Chara",
  "test8378",
  "VexatiousCheff",
  "vex", # VexatiousCheff
  "DBYT3",
  "Yup_This_Is_My_Name",
  "vorcazm",
  "Treagus", # vorcazm
  "The_Mega_Force",
  "Boringfish",
  "cock unsucker",
  "TylerDC",
  "Staticwork",
  "crit a cola drinker",
  "You have been banned."
]

# Problematic hackers? We get rid of them by banning their user IDs
IGNORED_IDS = [
   63944, # Kronogenics
  115572, # Mishu
  128613, # cock unsucker
  201322, # dimitry008
  146275, # Puce
  243184, # Player
  253161, # Chara
  253072, # test8378
  221472, # VexatiousCheff / vex
  276273, # DBYT3
  291743, # Yup_This_Is_My_Name
   75839, # vorcazm / Treagus
  307030, # The_Mega_Force
  298531, # Boringfish
   76223, # TylerDC
  325245, # Staticwork
  202167, # crit a cola drinker
  173617  # You have been banned.
]

# Patched runs from legitimate players because they were done
# with older versions of levels and the scores are now incorrect.
# @params: maximum replay id of incorrect scores, score adjustment required
PATCH_RUNS = {
  :episode => {
    182 => [695142, -42], #  S-C-12
    217 => [1165074, -8], #  S-C-19
    509 => [2010381, -6]  # SU-E-05
  },
  :level => {
     910 => [286360, -42], #  S-C-12-00
    1089 => [225710,  -8], #  S-C-19-04
    2549 => [2000000, -6]  # SU-E-05-04
  },
  :story => {
  },
  :userlevel => {
  }
}

# Delete individual runs
PATCH_IND_DEL = {
  :episode   => [
    5035576, # proxy17585's SI-C-00
    5073211  # HamSandwich's SI-D-00
  ],
  :level     => [
    3572785, # SuperVolcano's S-B-00-01
    3622469  # HamSandwich's S-B-00-02
  ],
  :story     => [],
  :userlevel => []
}

# Patch individual runs (by changing score)
PATCH_IND_CHG = {
  :episode   => {
    5067031 => -6 # trance's SU-E-05
  },
  :level     => {
    3758900 => -6 # trance's SU-E-05-04
  },
  :story     => {},
  :userlevel => {}
}
