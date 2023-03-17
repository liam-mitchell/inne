# <--------------------------------------------------------------------------->
# <------                   DEVELOPMENT VARIABLES                       ------>
# <--------------------------------------------------------------------------->

TEST           = false  # Switch to the local test bot
TEST_REPORT    = false # Produces the report immediately once
SHOW_ERRORS    = true  # Log common error messages to the console
DO_NOTHING     = false # Don't execute any threads (see below for ind flags)
DO_EVERYTHING  = false # Execute all threads
RESPOND        = false  # Respond to pings / DMs (for testing)
BYEBUG         = false # Breakpoint right after loading the bot

# <--------------------------------------------------------------------------->
# <------                     LOGGING VARIABLES                         ------>
# <--------------------------------------------------------------------------->

LOG            = true  # Log stuff to the terminal (superseeds the next 5 ones)
LOG_INFO       = true  # Log info to the terminal
LOG_WARNINGS   = true  # Log warnings to the terminal
LOG_ERRORS     = true  # Log errors to the terminal
LOG_MSGS       = true  # Log mentions and DMs to outte
LOG_SUCCESS    = true  # Log successes
LOG_FANCY      = true  # Format logs (bold, colors...)
LOG_TO_FILE    = false # Export logs and errors into external file
LOG_SQL        = false # Log _all_ SQL queries to the terminal (for debugging)
LOG_REPORT     = false # Export new weekly scores to a file

# <--------------------------------------------------------------------------->
# <------                     INTERNAL VARIABLES                        ------>
# <--------------------------------------------------------------------------->

WAIT           = 1     # Seconds to wait between each iteration of the infinite while loops to prevent craziness
BENCHMARK      = false # Benchmark and log functions (for optimization)
BENCH_MSGS     = false # Benchmark functions _in messages_
DATABASE_ENV   = ENV['DATABASE_ENV'] || (TEST ? 'outte_test' : 'outte')
CONFIG         = 'db/config.yml'

# <--------------------------------------------------------------------------->
# <------                     NETWORK VARIABLES                         ------>
# <--------------------------------------------------------------------------->

OFFLINE_MODE   = false   # Disables most intensive online functionalities
OFFLINE_STRICT = false   # Disables all online functionalities of outte
RETRIES        = 50      # Redownload attempts for boards / demos
ATTEMPT_LIMIT  = 5       # Redownload attempts in general (bigger files)
INVALID_RESP   = '-1337' # N++'s server response when Steam ID is inactive
DEFAULT_TYPES  = ['Level', 'Episode'] # Default highscoreable types

UPDATE_SCORES_ON_LOTD = true # Update scores right before lotd (may delay post)

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

# Despite the bot being public, so that the botmaster does not need to be a mod
# of the server, we only allow select servers. Otherwise randos could add outte.
SERVER_WHITELIST = [
  SERVER_ID,          # N++
  535635802386857995  # Test server
]

# <--------------------------------------------------------------------------->
# <------                     DIRECTORY VARIABLES                       ------>
# <--------------------------------------------------------------------------->

# TODO: Create constants for all other relevant directories (e.g., screenies,
# migrations, userlevels, etc), and substitute all hardcoded references in the
# source code.
DIR_MAPPACKS = './db/mappacks'

# <--------------------------------------------------------------------------->
# <------                  MONKEY PATCHING VARIABLES                    ------>
# <--------------------------------------------------------------------------->

MONKEY_PATCH               = true # Enable monkey patches globally
MONKEY_PATCH_CORE          = true # Enable Kernel patches (must!)
MONKEY_PATCH_ACTIVE_RECORD = true # Enable ActiveRecord monkey patches (must!)
MONKEY_PATCH_DISCORDRB     = true # Enable Discordrb monkey patches (optional)

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
DATE_FORMAT_NPP   = "%Y-%m-%d-%H:%M"       # Date format used by N++
DATE_FORMAT_OUTTE = "%Y/%m/%d %H:%M"       # Date format used by outte
DATE_FORMAT_MYSQL = "%Y-%m-%d %H:%M:%S"    # Date format required by MySQL
DATE_FORMAT_LOG   = "%Y/%m/%d %H:%M:%S.%L" # Date format used for terminal logs

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
MISHU          = true               # MishNUB joke
MISHU_COOLDOWN = 30 * 60            # MishNUB cooldown
COOL           = true               # Emoji for CKC in leaderboards
FRUITS         = [                  # Emojis for the potato joke
  ':potato:',
  ':tomato:',
  ':eggplant:',
  ':peach:',
  ':carrot:',
  ':pineapple:',
  ':cucumber:',
  ':cheese:'
]

# <--------------------------------------------------------------------------->
# <------                       TASK VARIABLES                          ------>
# <--------------------------------------------------------------------------->

# Individual flags for each thread / task
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

# Update frequencies for each task, in seconds
STATUS_UPDATE_FREQUENCY     =             5 * 60
TWITCH_UPDATE_FREQUENCY     =                 60
HIGHSCORE_UPDATE_FREQUENCY  =       24 * 60 * 60
HISTORY_UPDATE_FREQUENCY    =       24 * 60 * 60
DEMO_UPDATE_FREQUENCY       =       24 * 60 * 60
LEVEL_UPDATE_FREQUENCY      =       24 * 60 * 60
EPISODE_UPDATE_FREQUENCY    =   7 * 24 * 60 * 60
STORY_UPDATE_FREQUENCY      =  30 * 24 * 60 * 60 # Not used (published 1st of each month)
REPORT_UPDATE_FREQUENCY     =       24 * 60 * 60
REPORT_UPDATE_SIZE          =   7 * 24 * 60 * 60
SUMMARY_UPDATE_SIZE         =   1 * 24 * 60 * 60
USERLEVEL_SCORE_FREQUENCY   =       24 * 60 * 60
USERLEVEL_UPDATE_RATE       =                 15
USERLEVEL_HISTORY_FREQUENCY =       24 * 60 * 60
USERLEVEL_REPORT_FREQUENCY  =       24 * 60 * 60
USERLEVEL_TAB_FREQUENCY     =       24 * 60 * 60
USERLEVEL_DOWNLOAD_CHUNK    =                100

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
# <------                       GAME VARIABLES                          ------>
# <--------------------------------------------------------------------------->

MODES = {
  -1 => "all",
   0 => "solo",
   1 => "coop",
   2 => "race"
}

# Properties of the different playing TYPES
# NOTE: Do NOT change order, as their index is important
#   name       - Name of the type AND of the Rails model class
#   slots      - IDs reserved by N++ to this mode in the db
#   min_scores - Max-min amount of scores to be taken into consideration for average rankings
TYPES = [
  { name: 'Level',   slots: 20000, min_scores: 100 },
  { name: 'Episode', slots:  4000, min_scores:  50 },
  { name: 'Story',   slots:   800, min_scores:  10 }
]

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

# TODO: Complete this with all other modes
# TODO: Use this wherever TABS is being used, and also in parse_tabs, then delete TABS
TABS_NEW = {
  SI: {
    code:   'SI',
    mode:   0,
    name:   'Intro',
    start:  0,
    size:   125,
    files:  { 'SI' => 125 },
    x:      false,
    secret: false
  },
  S: {
    code:   'S',
    mode:   0,
    name:   'Solo',
    start:  600,
    size:   600,
    files:  { 'S' => 600 },
    x:      true,
    secret: false
  },
  SL: 
  {
    code:   'SL',
    mode:   0,
    name:   'Legacy',
    start:  1200,
    size:   600,
    files:  { 'SL' => 600 },
    x:      true,
    secret: false
  },
  SU: {
    code:   'SU',
    mode:   0,
    name:   'Ultimate',
    start:  2400,
    size:   600,
    files:  { 'S2' => 600 },
    x:      true,
    secret: false
  },
  SS: {
    code:   '?',
    mode:   0,
    name:   'Secret',
    start:  1800,
    size:   120,
    files:  { 'SS' => 120 },
    x:      true,
    secret: true,
  },
  SS2: {
    code:   '!',
    mode:   0,
    name:   'Ultimate Secret',
    start:  3000,
    size:   120,
    files:  { 'SS2' => 120 },
    x:      true,
    secret: true
  }
}

# <--------------------------------------------------------------------------->
# <------                    HIGHSCORING VARIABLES                      ------>
# <--------------------------------------------------------------------------->

MIN_TIES = 3 # Minimum number of ties for 0th to be considered maxable
MAX_SECS = 5 # Difference in seconds to consider two dates equal (for navigation)
MAXMIN_SCORES = 100   # max-min number of highscores to appear in average point rankings

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
