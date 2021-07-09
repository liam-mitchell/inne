# IMPORTANT NOTE: To set up the bot for the first time:
#
# 1) Set up the following environment variable:
# 1.1) DISCORD_TOKEN - This is Discord's application token / secret for your bot.
# 2) Set up the following 2 environment variables (optional):
# 2.1) TWITCH_SECRET - This is your Twitch app's secret, if you want to be able to
#                      use the Twitch functionality. Otherwise, disable the
#                      variable LOOKUP_TWITCH down below.
# 2.2) DISCORD_TOKEN_TEST - Same as DISCORD_TOKEN, but for a secondary development
#                           bot. If you don't care about this, never enable the
#                           variable TEST down below.
# 3) Configure the "outte" environment of the config file in ./db/config.yml,
#    or create a new one and rename the DATABASE_ENV variable down below.
# 4) Configure the "outte_test" environment of the config file (optional).
# 5) Create, migrate and seed a database named "inne". Make sure to use MySQL
#    with utf8mb4 encoding and collation. Alternatively, contact whoever is taking
#    care of the bot for a copy of the database (see Contact).
# 6) Install Ruby 2.7 to maximize compatibility, then run the Bundler to
#    obtain the correct version of all gems (libraries).
#
# Contact: https://discord.gg/nplusplus

require 'discordrb'
require 'json'
require 'net/http'
require 'thread'
require 'yaml'
require 'byebug'
require_relative 'models.rb'
require_relative 'messages.rb'

TEST           = true  # Switch to the local test bot
LOG            = false # Export logs and errors into external file
LOG_REPORT     = true  # Log new weekly scores that appear in the report
ATTEMPT_LIMIT  = 5     # Redownload attempts before skipping
WAIT           = 1     # Seconds to wait between each iteration of the infinite while loops to prevent craziness
DATABASE_ENV   = ENV['DATABASE_ENV'] || (TEST ? 'outte_test' : 'outte')
CONFIG         = YAML.load_file('db/config.yml')[DATABASE_ENV]
SERVER_ID      = 197765375503368192 # N++ Server
CHANNEL_ID     = 210778111594332181 # #highscores
USERLEVELS_ID  = 221721273405800458 # #mapping
NV2_ID         = 197774025844457472 # #nv2
CONTENT_ID     = 197793786389200896 # #content-creation
TWITCH_ROLE    = "Voyeur"           # Discord role for those that want to be pinged when a new stream happens
POTATO         = true               # joke they have in the nv2 channel
POTATO_RATE    = 1                  # seconds between potato checks
POTATO_FREQ    = 3 * 60 * 60        # 3 hours between potato delivers
MISHU          = true               # MishNUB joke
MISHU_COOLDOWN = 30 * 60            # MishNUB cooldown

OFFLINE_MODE      = false # Disables most intensive online functionalities
OFFLINE_STRICT    = false # Disables all online functionalities of outte
DO_NOTHING        = true  # 'true' sets all the following ones to false
DO_EVERYTHING     = false # 'true' sets all the following ones to true
UPDATE_STATUS     = true  # Thread to regularly update the bot's status
UPDATE_TWITCH     = true  # Thread to regularly look up N related Twitch streams
UPDATE_SCORES     = true  # Thread to regularly download Metanet's scores
UPDATE_HISTORY    = true  # Thread to regularly update highscoring histories
UPDATE_DEMOS      = true  # Thread to regularly download missing Metanet demos
UPDATE_LEVEL      = true  # Thread to regularly publish level of the day
UPDATE_EPISODE    = true  # Thread to regularly publish episode of the week
UPDATE_STORY      = true  # Thread to regularly publish column of the month
UPDATE_USERLEVELS = true  # Thread to regularly download newest userlevel scores
UPDATE_USER_GLOB  = true  # Thread to continuously (but slowly) download all userlevel scores
UPDATE_USER_HIST  = true  # Thread to regularly update userlevel highscoring histories
REPORT_METANET    = true  # Thread to regularly post Metanet's highscoring report
REPORT_USERLEVELS = true  # Thread to regularly post userlevels' highscoring report

STATUS_UPDATE_FREQUENCY     = CONFIG['status_update_frequency']     ||            5 * 60 # every 5 mins
TWITCH_UPDATE_FREQUENCY     = CONFIG['twitch_update_frequency']     ||                60 # every 1 min
HIGHSCORE_UPDATE_FREQUENCY  = CONFIG['highscore_update_frequency']  ||      24 * 60 * 60 # daily
HISTORY_UPDATE_FREQUENCY    = CONFIG['history_update_frequency']    ||      24 * 60 * 60 # daily
DEMO_UPDATE_FREQUENCY       = CONFIG['demo_update_frequency']       ||      24 * 60 * 60 # daily
LEVEL_UPDATE_FREQUENCY      = CONFIG['level_update_frequency']      ||      24 * 60 * 60 # daily
EPISODE_UPDATE_FREQUENCY    = CONFIG['episode_update_frequency']    ||  7 * 24 * 60 * 60 # weekly
STORY_UPDATE_FREQUENCY      = CONFIG['story_update_frequency']      || 30 * 24 * 60 * 60 # monthly (roughly)
REPORT_UPDATE_FREQUENCY     = CONFIG['report_update_frequency']     ||      24 * 60 * 60 # daily
REPORT_UPDATE_SIZE          = CONFIG['report_period']               ||  7 * 24 * 60 * 60 # last 7 days
USERLEVEL_SCORE_FREQUENCY   = CONFIG['userlevel_score_frequency']   ||      24 * 60 * 60 # daily
USERLEVEL_UPDATE_RATE       = CONFIG['userlevel_update_rate']       ||                15 # every 5 secs
USERLEVEL_HISTORY_FREQUENCY = CONFIG['userlevel_history_frequency'] ||      24 * 60 * 60 # daily
USERLEVEL_REPORT_FREQUENCY  = CONFIG['userlevel_report_frequency']  ||      24 * 60 * 60 # daily
USERLEVEL_DOWNLOAD_CHUNK    = CONFIG['userlevel_download_chunk']    ||               100 # 100 maps at a time

def log(msg)
  puts "[INFO] [#{Time.now}] #{msg}"
  open('LOG', 'a') { |f| f.puts "[INFO] [#{Time.now}] #{msg}" } if LOG
end

def err(msg)
  STDERR.puts "[ERROR] [#{Time.now}] #{msg}"
  open('LOG', 'a') { |f| f.puts "[ERROR] [#{Time.now}] #{msg}" } if LOG
end

def get_current(type)
  type.find_by(name: GlobalProperty.find_by(key: "current_#{type.to_s.downcase}").value)
end

def set_current(type, curr)
  GlobalProperty.find_or_create_by(key: "current_#{type.to_s.downcase}").update(value: curr.name)
end

def get_next(type)
  ret = nil
  while ret.nil?
    t = type.where(completed: nil).sample
    ret = t if t.scores[0].score != t.scores.last.score
  end
  ret.update(completed: true)
  ret
end

def get_next_update(type)
  Time.parse(GlobalProperty.find_by(key: "next_#{type.to_s.downcase}_update").value)
end

def set_next_update(type, time)
  GlobalProperty.find_or_create_by(key: "next_#{type.to_s.downcase}_update").update(value: time.to_s)
end

def get_saved_scores(type)
  JSON.parse(GlobalProperty.find_by(key: "saved_#{type.to_s.downcase}_scores").value)
end

def set_saved_scores(type, curr)
  GlobalProperty.find_or_create_by(key: "saved_#{type.to_s.downcase}_scores")
    .update(value: curr.scores.to_json(include: {player: {only: :name}}))
end

def get_last_steam_id
  GlobalProperty.find_or_create_by(key: "last_steam_id").value
end

def set_last_steam_id(id)
  GlobalProperty.find_or_create_by(key: "last_steam_id").update(value: id)
end

def update_last_steam_id
  current   = (User.find_by(steam_id: get_last_steam_id).id || 0) rescue 0
  next_user = (User.where.not(steam_id: nil).where('id > ?', current).first || User.where.not(steam_id: nil).first) rescue nil
  set_last_steam_id(next_user.steam_id) if !next_user.nil?
end

def activate_last_steam_id
  p = User.find_by(steam_id: get_last_steam_id)
  p.update(last_active: Time.now) if !p.nil?
end

def deactivate_last_steam_id
  p = User.find_by(steam_id: get_last_steam_id)
  p.update(last_inactive: Time.now) if !p.nil?   
end

# This corrects a datetime in the database when it's out of
# phase (e.g. after a long downtime of the bot).
def correct_time(time, frequency)
  time -= frequency while time > Time.now
  time += frequency while time < Time.now
  time
end

# Pings a role by name (returns ping string)
def ping(rname)
  server = TEST ? $bot.servers.values.first : $bot.servers[SERVER_ID]
  if server.nil?
    log("server not found")
    return ""
  end

  role = server.roles.select{ |r| r.name == rname }.first
  if role != nil
    if role.mentionable
      return role.mention
    else
      log("role #{rname} in server #{server.name} not mentionable")
      return ""
    end
  else
    log("role #{rname} not found in server #{server.name}")
    return ""
  end
end

# Periodically perform several useful tasks:
# - Update scores for lotd, eotw and cotm.
# - Update database with newest userlevels from all playing modes.
# - Update bot's status (it only lasts so much).
def update_status
  while(true)
    sleep(WAIT) # prevent crazy loops
    if !OFFLINE_STRICT
      (0..2).each do |mode| Userlevel.browse(10, 0, mode, true) rescue next end
      $status_update = Time.now.to_i
      get_current(Level).update_scores
      get_current(Episode).update_scores
      get_current(Story).update_scores
    end
    $bot.update_status("online", "inne's evil cousin", nil, 0, false, 0)
    sleep(STATUS_UPDATE_FREQUENCY)
  end
rescue
  retry
end

def update_twitch
  if $content_channel.nil?
    err("not connected to a channel, not sending twitch report")
    sleep(WAIT)
    raise
  end

  while(true)
    sleep(WAIT)
    old_streams = $twitch_streams.dup
    Twitch::update_twitch_streams
    $twitch_streams.each{ |game, list|
      if old_streams.key?(game)
        list.each{ |stream|
          if !old_streams[game].map{ |s| s['id'] }.include?(stream['id'])
            $content_channel.send_message("#{ping(TWITCH_ROLE)} `#{stream['user_name']}` started streaming **#{game}**! `#{stream['title']}` <https://www.twitch.tv/#{stream['user_login']}>")
          end
        }
      end
    }
    sleep(TWITCH_UPDATE_FREQUENCY)
  end  
rescue => e
  err(e)
  retry
end

def download_demos
  log("updating demos...")
  ids = Demo.where.not(demo: nil).or(Demo.where(expired: true)).pluck(:id)
  archives = Archive.where.not(id: ids).pluck(:id, :replay_id, :highscoreable_type)
  count = archives.size
  archives.each_with_index do |ar, i|
    attempts ||= 0
    ActiveRecord::Base.transaction do
      demo = Demo.find_or_create_by(id: ar[0])
      demo.update(replay_id: ar[1], htype: Demo.htypes[ar[2].to_s.downcase])
      demo.update_demo
    end
  rescue => e
    err("error updating demo with ID #{ar[0].to_s}: #{e}")
    ((attempts += 1) < ATTEMPT_LIMIT) ? retry : next
  end
  log("updated demos")
  return true
rescue => e
  err("error updating demos: #{e}")
  return false
end

def start_demos
  while true
    sleep(WAIT) # prevent crazy loops
    next_demo_update = correct_time(get_next_update('demo'), DEMO_UPDATE_FREQUENCY)
    set_next_update('demo', next_demo_update)
    delay = next_demo_update - Time.now
    sleep(delay) unless delay < 0
    next if !download_demos
  end
rescue => e
  err("error updating demos: #{e}")
  retry
end

def send_report
  log("sending highscoring report...")
  if $channel.nil?
    err("not connected to a channel, not sending highscoring report")
    return false
  end

  base = Time.new(2020, 9, 3, 0, 0, 0, "+00:00").to_i # when archiving begun
  time = [Time.now.to_i - REPORT_UPDATE_SIZE, base].max
  now  = Time.now.to_i
  pad  = [2, DEFAULT_PADDING, 6, 6, 6, 5, 4]
  log  = [] if LOG_REPORT

  changes = Archive.where("unix_timestamp(date) > #{time}")
                   .order('date desc')
                   .map{ |ar| [ar.metanet_id, ar.find_rank(time), ar.find_rank(now), ar.highscoreable, ar.score] }
                   .group_by{ |s| s[0] }
                   .map{ |id, scores|
                         [
                           id,
                           scores.group_by{ |s| s[3] }
                                 .map{ |highscoreable, versions|
                                       max = versions.map{ |v| v[4] }.max
                                       versions.select{ |v| v[4] == max }.first
                                     }
                         ]
                       }
                   .map{ |id, scores|
                         log << [Player.find_by(metanet_id: id).name, scores.sort_by{ |s| [s[2], s[3].id] }] if LOG_REPORT
                         {
                           player: Player.find_by(metanet_id: id).name,
                           points: scores.map{ |s| s[1] - s[2] }.sum,
                           top20s: scores.select{ |s| s[1] == 20 }.size,
                           top10s: scores.select{ |s| s[1] > 9 && s[2] <= 9 }.size,
                           top05s: scores.select{ |s| s[1] > 4 && s[2] <= 4 }.size,
                           zeroes: scores.select{ |s| s[2] == 0 }.size
                         }
                       }
                   .sort_by{ |p| -p[:points] }
                   .each_with_index
                   .map{ |p, i|
                         values = p.values.prepend(i)
                         values.each_with_index.map{ |v, j|
                           s = v.to_s.rjust(pad[j], " ")[0..pad[j]-1]
                           s += " |" if [0, 1, 2].include?(j)
                           s
                         }.join(" ")
                       }
                   .take(20)
                   .join("\n")

  header = ["", "Player", "Points", "Top20s", "Top10s", "Top5s", "0ths"]
             .each_with_index
             .map{ |h, i|
                   s = h.ljust(pad[i], " ")
                   s += " |" if [0, 1, 2].include?(i)
                   s
                 }
             .join(" ")
  sep = "-" * (pad.sum + pad.size + 5)

  $channel.send_message("**The highscoring report!** [Last 7 days]```#{header}\n#{sep}\n#{changes}```")
  if LOG_REPORT
    log_text = log.sort_by{ |name, scores| name }.map{ |name, scores|
      scores.map{ |s|
        name[0..14].ljust(15, " ") + " " + (s[1] == 20 ? " x  " : s[1].ordinalize).rjust(4, "0") + "->" + s[2].ordinalize.rjust(4, "0") + " " + s[3].name.ljust(10, " ") + " " + ("%.3f" % (s[4].to_f / 60.0))
      }.join("\n")
    }.join("\n")
    File.write("report_log", log_text)
  end

  log("highscoring report sent")  
  return true
end

def start_report
  begin
    while true
      sleep(WAIT) # prevent crazy loops
      next_report_update = correct_time(get_next_update('report'), REPORT_UPDATE_FREQUENCY)
      set_next_update('report', next_report_update)
      delay = next_report_update - Time.now
      sleep(delay) unless delay < 0
      next if !send_report
    end
  rescue => e
    err("error sending highscoring report: #{e}")
    retry
  end
end

def send_userlevel_report
  log("sending userlevel highscoring report...")
  if $channel.nil?
    err("not connected to a channel, not sending highscoring report")
    return false
  end

  zeroes = Userlevel.rank(:rank, true, 0)
                    .each_with_index
                    .map{ |p, i| "#{"%02d" % i}: #{format_string(p[0].name)} - #{"%3d" % p[1]}" }
                    .join("\n")
  points = Userlevel.rank(:points, false, 0)
                    .each_with_index
                    .map{ |p, i| "#{"%02d" % i}: #{format_string(p[0].name)} - #{"%3d" % p[1]}" }
                    .join("\n")

  $mapping_channel.send_message("**Userlevel highscoring update [Newest #{USERLEVEL_REPORT_SIZE} maps]**")
  $mapping_channel.send_message("Userlevel 0th rankings with ties on #{Time.now.to_s}:\n```#{zeroes}```")
  $mapping_channel.send_message("Userlevel point rankings on #{Time.now.to_s}:\n```#{points}```")
  log("userlevel highscoring report sent")
  return true
end

def start_userlevel_report
  begin
    while true
      sleep(WAIT) # prevent crazy loops
      next_userlevel_report_update = correct_time(get_next_update('userlevel_report'), USERLEVEL_REPORT_FREQUENCY)
      set_next_update('userlevel_report', next_userlevel_report_update)
      delay = next_userlevel_report_update - Time.now
      sleep(delay) unless delay < 0
      next if !send_userlevel_report
    end
  rescue => e
    err("error sending userlevel highscoring report: #{e}")
    retry
  end
end

def download_high_scores
  log("downloading high scores...")
  # We handle exceptions within each instance so that they don't force
  # a retry of the whole function.
  # Note: Exception handling inside do blocks requires ruby 2.5 or greater.
  [Level, Episode, Story].each do |type|
    type.all.each do |o|
      attempts ||= 0
      o.update_scores
    rescue => e
      err("error updating high scores for #{o.class.to_s.downcase} #{o.id.to_s}: #{e}")
      ((attempts += 1) <= ATTEMPT_LIMIT) ? retry : next
    end
  end
  log("downloaded high scores")
  return true
rescue
  err("error download high scores")
  return false
end

def start_high_scores
  begin
    while true
      sleep(WAIT) # prevent crazy loops
      next_score_update = correct_time(get_next_update('score'), HIGHSCORE_UPDATE_FREQUENCY)
      set_next_update('score', next_score_update)
      delay = next_score_update - Time.now
      sleep(delay) unless delay < 0
      next if !download_high_scores
    end
  rescue => e
    err("error updating high scores: #{e}")
    retry
  end
end

def update_histories
  log("updating histories...")
  now = Time.now
  [:SI, :S, :SU, :SL, :SS, :SS2].each do |tab|
    [Level, Episode, Story].each do |type|
      next if (type == Episode || type == Story) && [:SS, :SS2].include?(tab)

      [1, 5, 10, 20].each do |rank|
        [true, false].each do |ties|
          rankings = Score.rank(:rank, type, tab, ties, rank - 1, true)
          attrs    = RankHistory.compose(rankings, type, tab, rank, ties, now)
          ActiveRecord::Base.transaction do
            RankHistory.create(attrs)
          end
        end
      end

      rankings = Score.rank(:points, type, tab, false, nil, true)
      attrs    = PointsHistory.compose(rankings, type, tab, now)
      ActiveRecord::Base.transaction do
        PointsHistory.create(attrs)
      end

      rankings = Score.rank(:score, type, tab, false, nil, true)
      attrs    = TotalScoreHistory.compose(rankings, type, tab, now)
      ActiveRecord::Base.transaction do
        TotalScoreHistory.create(attrs)
      end
    end
  end
  log("updated highscore histories")
  return true
rescue => e
  err("error updating histories: #{e}")
  return false  
end

def start_histories
  while true
    sleep(WAIT) # prevent crazy loops
    next_history_update = correct_time(get_next_update('history'), HISTORY_UPDATE_FREQUENCY)
    set_next_update('history', next_history_update)
    delay = next_history_update - Time.now
    sleep(delay) unless delay < 0
    next if !update_histories
  end
rescue => e
  err("error updating highscore histories: #{e}")
  retry
end

def update_userlevel_histories
  log("updating userlevel histories...")
  now = Time.now

  [-1, 1, 5, 10, 20].each{ |rank|
    rankings = Userlevel.rank(rank == -1 ? :points : :rank, rank == 1 ? true : false, rank - 1, true)
    attrs    = UserlevelHistory.compose(rankings, rank, now)
    ActiveRecord::Base.transaction do
      UserlevelHistory.create(attrs)
    end
  }

  log("updated userlevel histories")
  return true   
rescue => e
  err("error updating userlevel histories: #{e}")
  return false
end

def start_userlevel_histories
  while true
    next_userlevel_history_update = correct_time(get_next_update('userlevel_history'), USERLEVEL_HISTORY_FREQUENCY)
    set_next_update('userlevel_history', next_userlevel_history_update)
    delay = next_userlevel_history_update - Time.now
    sleep(delay) unless delay < 0
    next if !update_userlevel_histories
  end
rescue => e
  err("error updating userlevel highscore histories: #{e}")
  retry
end

def download_userlevel_scores
  log("updating newest userlevel scores...")
  Userlevel.where(mode: :solo).order(id: :desc).take(USERLEVEL_REPORT_SIZE).each do |u|
    attempts ||= 0
    u.update_scores
  rescue => e
    err("error updating highscores for userlevel #{u.id}: #{e}")
    ((attempts += 1) <= ATTEMPT_LIMIT) ? retry : next
  end
  log("updated userlevel scores")
  return true
rescue => e
  err("error updating userlevel highscores: #{e}")
  return false
end

def start_userlevel_scores
  while true
    next_userlevel_score_update = correct_time(get_next_update('userlevel_score'), USERLEVEL_SCORE_FREQUENCY)
    set_next_update('userlevel_score', next_userlevel_score_update)
    delay = next_userlevel_score_update - Time.now
    sleep(delay) unless delay < 0
    next if !download_userlevel_scores
  end
rescue => e
  err("error downloading userlevel highscores: #{e}")
  retry
end

def update_all_userlevels_chunk
  log("updating next userlevel chunk scores...")
  Userlevel.where(mode: :solo).order('last_update IS NOT NULL, last_update').take(USERLEVEL_DOWNLOAD_CHUNK).each do |u|
    sleep(USERLEVEL_UPDATE_RATE)
    attempts ||= 0
    u.update_scores
  rescue => e
    err("error updating highscores for userlevel #{u.id}: #{e}")
    ((attempts += 1) <= ATTEMPT_LIMIT) ? retry : next
  end
  log("updated userlevel chunk scores")
  return true
rescue => e
  err("error updating userlevel chunk scores: #{e}")
  return false
end

def update_all_userlevels
  log("updating all userlevel scores...")
  while true
    update_all_userlevels_chunk
    sleep(WAIT)
  end
rescue => e
  err("error updating all userlevel scores: #{e}")
  retry
end

def send_channel_screenshot(name, caption)
  name = name.gsub(/\?/, 'SS').gsub(/!/, 'SS2')
  screenshot = "screenshots/#{name}.jpg"
  if File.exist? screenshot
    $channel.send_file(File::open(screenshot), caption: caption)
  else
    $channel.send_message(caption + "\nI don't have a screenshot for this one... :(")
  end
end

def send_channel_diff(level, old_scores, since)
  return if level.nil? || old_scores.nil?

  diff = level.format_difference(old_scores)
  $channel.send_message("Score changes on #{level.format_name} since #{since}:\n```#{diff}```")
end

def send_channel_reminder
  $channel.send_message("Also, remember that the current episode of the week is #{get_current(Episode).format_name}.")
end

def send_channel_story_reminder
  $channel.send_message("Also, remember that the current column of the month is #{get_current(Story).format_name}.")
end

def send_channel_next(type)
  log("sending next #{type.to_s.downcase}")
  if $channel.nil?
    err("not connected to a channel, not sending level of the day")
    return false
  end

  last = get_current(type)
  current = get_next(type)
  set_current(type, current)

  if current.nil?
    err("no more #{type.to_s.downcase}")
    return false
  end

  if !OFFLINE_STRICT
    if !last.nil?
      last.update_scores
    end
    current.update_scores
  end

  prefix = (type == Level ? "Time" : "It's also time")
  duration = (type == Level ? "day" : (type == Episode ? "week" : "month"))
  time = (type == Level ? "today" : (type == Episode ? "this week" : "this month"))
  since = (type == Level ? "yesterday" : (type == Episode ? "last week" : "last month"))
  typename = type != Story ? type.to_s.downcase : "column"

  caption = "#{prefix} for a new #{typename} of the #{duration}! The #{typename} for #{time} is #{current.format_name}."
  send_channel_screenshot(current.name, caption)
  $channel.send_message("Current #{OFFLINE_STRICT ? "(cached) " : ""}high scores:\n```#{current.format_scores(current.max_name_length)}```")

  if !OFFLINE_STRICT
    send_channel_diff(last, get_saved_scores(type), since)
  else
    $channel.send_message("Strict offline mode activated, not sending score differences.")
  end
  set_saved_scores(type, current)

  return true
end

def start_level_of_the_day
  begin
    episode_day = false
    story_day = false
    while true
      next_level_update = correct_time(get_next_update(Level), LEVEL_UPDATE_FREQUENCY)
      next_episode_update = correct_time(get_next_update(Episode), EPISODE_UPDATE_FREQUENCY)
      set_next_update(Level, next_level_update)
      set_next_update(Episode, next_episode_update)
      delay = next_level_update - Time.now
      sleep(delay) unless delay < 0

     if (UPDATE_LEVEL || DO_EVERYTHING) && !DO_NOTHING
        log("starting level of the day...")
        next if !send_channel_next(Level)
        log("sent next level, next update at #{get_next_update(Level).to_s}")
      end

      if (UPDATE_EPISODE || DO_EVERYTHING) && !DO_NOTHING && next_episode_update < Time.now
        sleep(30) # let discord catch up
        send_channel_next(Episode)
        episode_day = true
        log("sent next episode, next update at #{get_next_update(Episode).to_s}")
      end

      if (UPDATE_STORY || DO_EVERYTHING) && !DO_NOTHING && get_next_update(Story) < Time.now
        # we add days until we get to the first day of the next month
        next_story_update = get_next_update(Story)
        month = next_story_update.month
        next_story_update += LEVEL_UPDATE_FREQUENCY while next_story_update.month == month
        set_next_update(Story, next_story_update)
        sleep(30) # let discord catch up
        send_channel_next(Story)
        story_day = true
        log("sent next story, next update at #{get_next_update(Story).to_s}")
      end

      if !episode_day && (UPDATE_LEVEL || DO_EVERYTHING) && !DO_NOTHING then send_channel_reminder end
      if !story_day && (UPDATE_LEVEL || DO_EVERYTHING) && !DO_NOTHING then send_channel_story_reminder end
      episode_day = false
      story_day = false
    end
  rescue => e
    err("error updating level of the day: #{e}")
    retry
  end
end

def potato
  while true
    sleep(POTATO_RATE)
    next if $nv2_channel.nil? || $last_potato.nil?
    if Time.now.to_i - $last_potato.to_i >= POTATO_FREQ
      if $tomato
        $nv2_channel.send_message(":tomato:")
        $tomato = false
        log("tomatoed nv2")
      else
        $nv2_channel.send_message(":potato:")
        $tomato = true
        log("potatoed nv2")
      end
      $last_potato = Time.now.to_i
    end
  end
end

def mishnub(event)
  youmean = ["More like ", "You mean ", "Mish... oh, ", "Better known as ", "A.K.A. ", "Also known as "]
  amirite = [" amirite", " isn't that right", " huh", " am I right or what", " amirite or amirite"]
  fellas  = [" fellas", " boys", " guys", " lads", " fellow ninjas", " friends", " ninjafarians"]
  laugh   = [" :joy:", " lmao", " hahah", " lul", " rofl", "  <:moleSmirk:336271943546306561>", " <:Kappa:237591190357278721>", " :laughing:", " rolfmao"]
  if rand < 0.05 && (event.channel.type == 1 || $last_mishu.nil? || !$last_mishu.nil? && Time.now.to_i - $last_mishu >= MISHU_COOLDOWN)
    event.send_message(youmean.sample + "MishNUB," + amirite.sample + fellas.sample + laugh.sample) 
    $last_mishu = Time.now.to_i unless event.channel.type == 1
  end
end

def robot(event)
  start  = ["No! ", "Not at all. ", "Negative. ", "By no means. ", "Most certainly not. ", "Not true. ", "Nuh uh. "]
  middle = ["I can assure you he's not", "Eddy is not a robot", "Master is very much human", "Senpai is a ningen", "Mr. E is definitely human", "Owner is definitely a hooman", "Eddy is a living human being", "Eduardo es una persona"]
  ending = [".", "!", " >:(", " (ಠ益ಠ)", " (╯°□°)╯︵ ┻━┻"]
  event.send_message(start.sample + middle.sample + ending.sample)
end

def startup
  ActiveRecord::Base.establish_connection(CONFIG)
  log("initialized")
  log("next level update at #{get_next_update(Level).to_s}")
  log("next episode update at #{get_next_update(Episode).to_s}")
  log("next story update at #{get_next_update(Story).to_s}")
  log("next score update at #{get_next_update('score')}")
  sleep(2) # Let the connection catch up
end

def shutdown
  log("shutting down")
  $bot.stop
end

def watchdog
  sleep(3) while !$kill_threads
  shutdown
end

#$bot = Discordrb::Bot.new token: CONFIG['token'], client_id: CONFIG['client_id']
$bot = Discordrb::Bot.new token: (TEST ? ENV['DISCORD_TOKEN_TEST'] : ENV['DISCORD_TOKEN']), client_id: CONFIG['client_id']
$config          = CONFIG
$channel         = nil
$mapping_channel = nil
$nv2_channel     = nil
$content_channel = nil
$last_potato     = Time.now.to_i
$tomato          = false
$last_mishu      = nil
$status_update   = Time.now.to_i
$twitch_token    = nil
$twitch_streams  = {}

$bot.mention do |event|
  respond(event)
  log("mentioned by #{event.user.name}: #{event.content}")
end

$bot.private_message do |event|
  respond(event)
  log("private message from #{event.user.name}: #{event.content}")
end

$bot.message do |event|
  if event.channel == $nv2_channel
    $last_potato = Time.now.to_i
    $tomato = false
  end
  mishnub(event) if MISHU && event.content.downcase.include?("mishu")
  robot(event) if !!event.content[/eddy\s*is\s*a\s*robot/i]
end

puts "the bot's URL is #{$bot.invite_url}"

startup
trap("INT") { $kill_threads = true }

$bot.run(true)
puts "Established connection to servers: #{$bot.servers.map{ |id, s| s.name }.join(', ')}."
if !TEST
  $channel         = $bot.servers[SERVER_ID].channels.find{ |c| c.id == CHANNEL_ID }
  $mapping_channel = $bot.servers[SERVER_ID].channels.find{ |c| c.id == USERLEVELS_ID }
  $nv2_channel     = $bot.servers[SERVER_ID].channels.find{ |c| c.id == NV2_ID }
  $content_channel = $bot.servers[SERVER_ID].channels.find{ |c| c.id == CONTENT_ID }
  $last_potato = Time.now.to_i
  puts "Main channel: #{$channel.name}."            if !$channel.nil?
  puts "Mapping channel: #{$mapping_channel.name}." if !$mapping_channel.nil?
  puts "Nv2 channel: #{$nv2_channel.name}.        " if !$nv2_channel.nil?
  puts "Content channel: #{$content_channel.name}." if !$content_channel.nil?
end

# TODO: Put this inside thread to prevent it from blocking Ctrl+C
$twitch_token = Twitch::get_twitch_token
Twitch::update_twitch_streams

$threads = []
$threads << Thread.new { update_status }             if (UPDATE_STATUS     || DO_EVERYTHING) && !DO_NOTHING
$threads << Thread.new { update_twitch }             if (UPDATE_TWITCH     || DO_EVERYTHING) && !DO_NOTHING
$threads << Thread.new { start_high_scores }         if (UPDATE_SCORES     || DO_EVERYTHING) && !DO_NOTHING && !OFFLINE_MODE
$threads << Thread.new { start_demos }               if (UPDATE_DEMOS      || DO_EVERYTHING) && !DO_NOTHING && !OFFLINE_MODE
$threads << Thread.new { start_level_of_the_day }
$threads << Thread.new { start_userlevel_scores }    if (UPDATE_USERLEVELS || DO_EVERYTHING) && !DO_NOTHING && !OFFLINE_MODE
$threads << Thread.new { update_all_userlevels }     if (UPDATE_USER_GLOB  || DO_EVERYTHING) && !DO_NOTHING && !OFFLINE_MODE
$threads << Thread.new { start_userlevel_histories } if (UPDATE_USER_HIST  || DO_EVERYTHING) && !DO_NOTHING && !OFFLINE_MODE
$threads << Thread.new { start_report }              if (REPORT_METANET    || DO_EVERYTHING) && !DO_NOTHING && !OFFLINE_MODE
$threads << Thread.new { start_userlevel_report }    if (REPORT_USERLEVELS || DO_EVERYTHING) && !DO_NOTHING && !OFFLINE_MODE
$threads << Thread.new { potato }                    if POTATO

wd = Thread.new { watchdog }
wd.join
