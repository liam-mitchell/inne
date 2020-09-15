require 'discordrb'
require 'json'
require 'net/http'
require 'thread'
require 'yaml'
require 'byebug'
require_relative 'models.rb'
require_relative 'messages.rb'

TEST          = true # Switch to the local test bot
LOG           = false # Export logs and errors into external file
ATTEMPT_LIMIT = 5     # Redownload attempts before skipping
DATABASE_ENV  = ENV['DATABASE_ENV'] || (TEST ? 'outte_test' : 'outte')
CONFIG        = YAML.load_file('db/config.yml')[DATABASE_ENV]
SERVER_ID     = 197765375503368192 # N++ Server
CHANNEL_ID    = 210778111594332181 # #highscores
USERLEVELS_ID = 221721273405800458 # #mapping

DO_NOTHING        = false # 'true' sets all the following ones to false
DO_EVERYTHING     = false # 'true' sets all the following ones to true
UPDATE_STATUS     = false # Thread to regularly update the bot's status
UPDATE_SCORES     = false # Thread to regularly download Metanet's scores
UPDATE_DEMOS      = false # Thread to regularly download missing Metanet demos
UPDATE_LEVEL      = false # Thread to regularly publish level of the day
UPDATE_EPISODE    = false # Thread to regularly publish episode of the week
UPDATE_STORY      = false # Thread to regularly publish column of the month
UPDATE_USERLEVELS = false # Thread to regularly download userlevel scores
REPORT_METANET    = false # Thread to regularly post Metanet's highscoring report
REPORT_USERLEVELS = true # Thread to regularly post userlevels' highscoring report

STATUS_UPDATE_FREQUENCY    = CONFIG['status_update_frequency']    ||            5 * 60 # every 5 mins
HIGHSCORE_UPDATE_FREQUENCY = CONFIG['highscore_update_frequency'] ||      24 * 60 * 60 # daily
DEMO_UPDATE_FREQUENCY      = CONFIG['demo_update_frequency']      ||      24 * 60 * 60 # daily
LEVEL_UPDATE_FREQUENCY     = CONFIG['level_update_frequency']     ||      24 * 60 * 60 # daily
EPISODE_UPDATE_FREQUENCY   = CONFIG['episode_update_frequency']   ||  7 * 24 * 60 * 60 # weekly
STORY_UPDATE_FREQUENCY     = CONFIG['story_update_frequency']     || 30 * 24 * 60 * 60 # monthly (roughly)
USERLEVEL_SCORE_FREQUENCY  = CONFIG['userlevel_score_frequency']  ||      24 * 60 * 60 # daily
REPORT_UPDATE_FREQUENCY    = CONFIG['report_update_frequency']    ||      24 * 60 * 60 # daily
REPORT_UPDATE_SIZE         = CONFIG['report_period']              ||  7 * 24 * 60 * 60 # last 7 days
USERLEVEL_REPORT_FREQUENCY = CONFIG['userlevel_report_frequency'] ||      24 * 60 * 60 # daily
USERLEVEL_REPORT_SIZE      = CONFIG['userlevel_report_size']      ||               500 # last 500 maps

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
  current = User.find_by(steam_id: get_last_steam_id).id
  next_user = User.where.not(steam_id: nil).where('id > ?', current).first || User.where.not(steam_id: nil).first
  set_last_steam_id(next_user.steam_id) if !next_user.nil?
end

# This corrects a datetime in the database when it's out of
# phase (e.g. after a long downtime of the bot).
def correct_time(time, frequency)
  time -= frequency while time > Time.now
  time += frequency while time < Time.now
  time
end

# Periodically perform several useful tasks:
# - Update scores for lotd, eotw and cotm.
# - Update database with newest userlevels from all playing modes.
# - Update bot's status (it only lasts so much).
def update_status
  ActiveRecord::Base.establish_connection(CONFIG)
  sleep(5) # Letting the database catch up

  while(true)
    get_current(Level).update_scores
    get_current(Episode).update_scores
    get_current(Story).update_scores
    (0..2).each do |mode| Userlevel.browse(10, 0, mode, true) rescue next end
    $bot.update_status("online", "inne's evil cousin", nil, 0, false, 0)
    sleep(STATUS_UPDATE_FREQUENCY)
  end
rescue
  retry
end

def download_high_scores
  ActiveRecord::Base.establish_connection(CONFIG)
  sleep(5) # Letting the database catch up

  begin
    while true
      log("updating high scores...")

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

      log("updated high scores. updating rankings...")

      now = Time.now
      [:SI, :S, :SU, :SL, :SS, :SS2].each do |tab|
        [Level, Episode, Story].each do |type|
          next if (type == Episode || type == Story) && [:SS, :SS2].include?(tab)

          [1, 5, 10, 20].each do |rank|
            [true, false].each do |ties|
              rankings = Player.rankings { |p| p.top_n_count(rank, type, tab, ties) }
              attrs = rankings.select { |r| r[1] > 0 }.map do |r|
                {
                  highscoreable_type: type.to_s,
                  rank: rank,
                  ties: ties,
                  tab: tab,
                  player: r[0],
                  count: r[1],
                  metanet_id: r[0].metanet_id,
                  timestamp: now
                }
              end

              ActiveRecord::Base.transaction do
                RankHistory.create(attrs)
              end
            end
          end

          rankings = Player.rankings { |p| p.points(type, tab) }
          attrs = rankings.select { |r| r[1] > 0 }.map do |r|
            {
              timestamp: now,
              tab: tab,
              highscoreable_type: type.to_s,
              player: r[0],
              metanet_id: r[0].metanet_id,
              points: r[1]
            }
          end

          ActiveRecord::Base.transaction do
            PointsHistory.create(attrs)
          end

          rankings = Player.rankings { |p| p.total_score(type, tab) }
          attrs = rankings.select { |r| r[1] > 0 }.map do |r|
            {
              timestamp: now,
              tab: tab,
              highscoreable_type: type.to_s,
              player: r[0],
              metanet_id: r[0].metanet_id,
              score: r[1]
            }
          end

          ActiveRecord::Base.transaction do
            TotalScoreHistory.create(attrs)
          end
        end
      end

      next_score_update = correct_time(get_next_update('score'), HIGHSCORE_UPDATE_FREQUENCY)
      set_next_update('score', next_score_update)
      delay = next_score_update - Time.now

      log("updated rankings, next score update in #{delay} seconds")

      sleep(delay) unless delay < 0
    end
  rescue => e
    err("error updating high scores: #{e}")
    retry
  end
end

def download_demos
  ActiveRecord::Base.establish_connection(CONFIG)
  sleep(5)

  begin
    while true
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

      next_demo_update = correct_time(get_next_update('demo'), DEMO_UPDATE_FREQUENCY)
      set_next_update('demo', next_demo_update)
      delay = next_demo_update - Time.now
      log("updated demos, next demo update in #{delay} seconds")
      sleep(delay) unless delay < 0
    end
  rescue => e
    err("error downloading demos: #{e}")
    retry
  end
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
                           s = v.to_s.rjust(pad[j], " ")
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
  return true
end

def start_report
  ActiveRecord::Base.establish_connection(CONFIG)
  sleep(5)
  begin
    while true
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
  log("sending highscoring report...")
  if $channel.nil?
    err("not connected to a channel, not sending highscoring report")
    #return false
  end

  zeroths = UserlevelScore.where(tied_rank: 0)
                          .group(:player_id)
                          .order('count_id desc')
                          .count(:id)
                          .take(20)
                          .each_with_index
                          .map{ |p, i| "#{"%02d" % i}: #{format_string(UserlevelPlayer.find(p[0]).name)} - #{"%3d" % p[1]}" }
                          .join("\n")
  points = UserlevelScore.all
                         .group_by{ |s| s.player_id }
                         .map{ |p, scores| [UserlevelPlayer.find(p).name, scores.map{ |s| 20 - s.rank }.sum] }
                         .sort_by{ |p, points| -points }
                         .take(20)
                         .each_with_index
                         .map{ |p, i| "#{"%02d" % i}: #{format_string(p[0])} - #{"%3d" % p[1]}" }
                         .join("\n")

  $mapping_channel.send_message("**Uselevel highscoring report [Newest 500 maps]**")
  $mapping_channel.send_message("Userlevel 0th rankings on #{Time.now.to_s}:\n```#{zeroths}```")
  $mapping_channel.send_message("Userlevel point rankings on #{Time.now.to_s}:\n```#{points}```")
  return true
end

def start_userlevel_report
  ActiveRecord::Base.establish_connection(CONFIG)
  sleep(5)
  begin
    while true
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

def download_userlevel_scores
  ActiveRecord::Base.establish_connection(CONFIG)
  sleep(5)
  begin
    while true
      next_userlevel_score_update = correct_time(get_next_update('userlevel_score'), USERLEVEL_SCORE_FREQUENCY)
      set_next_update('userlevel_score', next_userlevel_score_update)
      delay = next_userlevel_score_update - Time.now
      sleep(delay) unless delay < 0
      log("updating userlevel scores...")

      # Remove all initial excess userlevel scores
      amount = UserlevelScore.distinct.count(:userlevel_id) - USERLEVEL_REPORT_SIZE
      if amount > 0
        UserlevelScore.pluck(:userlevel_id).uniq.sort.take(USERLEVEL_REPORT_SIZE).each{ |id|
          UserlevelScore.where(userlevel_id: id).destroy_all
        }
      end

      # Update scores for the desired amount of userlevels
      Userlevel.where(mode: :solo).order(id: :desc).take(USERLEVEL_REPORT_SIZE).each do |u|
        attempts ||= 0
        u.update_scores
        # Only remove older ones when we surpass the limit again, to prevent ending
        # up with less userlevels than desired.
        if UserlevelScore.distinct.count(:userlevel_id) > USERLEVEL_REPORT_SIZE
          min = UserlevelScore.minimum(:userlevel_id).to_i
          UserlevelScore.where(userlevel_id: min).destroy_all
        end
      rescue => e
        err("error updating highscores for userlevel #{u.id}: #{e}")
        ((attempts += 1) <= ATTEMPT_LIMIT) ? retry : next
      end
      log("updated userlevel scores")
    end
  rescue => e
    err("error updating userlevel highscores: #{e}")
    retry
  end
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

  if !last.nil?
    last.update_scores
  end
  current.update_scores

  prefix = (type == Level ? "Time" : "It's also time")
  duration = (type == Level ? "day" : (type == Episode ? "week" : "month"))
  time = (type == Level ? "today" : (type == Episode ? "this week" : "this month"))
  since = (type == Level ? "yesterday" : (type == Episode ? "last week" : "last month"))
  typename = type != Story ? type.to_s.downcase : "column"

  caption = "#{prefix} for a new #{typename} of the #{duration}! The #{typename} for #{time} is #{current.format_name}."
  send_channel_screenshot(current.name, caption)
  $channel.send_message("Current high scores:\n```#{current.format_scores(current.max_name_length)}```")

  send_channel_diff(last, get_saved_scores(type), since)
  set_saved_scores(type, current)

  return true
end

def start_level_of_the_day
  ActiveRecord::Base.establish_connection(CONFIG)
  sleep(5) # Letting the database catch up

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

      if !episode_day then send_channel_reminder end
      if !story_day then send_channel_story_reminder end
      episode_day = false
      story_day = false
    end
  rescue => e
    err("error updating level of the day: #{e}")
    retry
  end
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
$bot = Discordrb::Bot.new token: (TEST ? ENV['TOKEN_TEST'] : ENV['TOKEN']), client_id: CONFIG['client_id']
$channel = TEST ? nil : $bot.servers[SERVER_ID].channels.find{ |c| c.id == CHANNEL_ID }
$mapping_channel = TEST ? nil : $bot.servers[SERVER_ID].channels.find{ |c| c.id == USERLEVELS_ID }

$bot.mention do |event|
  respond(event)
  log("mentioned by #{event.user.name}: #{event.content}")
end

$bot.private_message do |event|
  respond(event)
  log("private message from #{event.user.name}: #{event.content}")
end

puts "the bot's URL is #{$bot.invite_url}"

startup
trap("INT") { $kill_threads = true }

$threads = []
$threads << Thread.new { update_status }             if (UPDATE_STATUS     || DO_EVERYTHING) && !DO_NOTHING
$threads << Thread.new { download_high_scores }      if (UPDATE_SCORES     || DO_EVERYTHING) && !DO_NOTHING
$threads << Thread.new { download_demos }            if (UPDATE_DEMOS      || DO_EVERYTHING) && !DO_NOTHING
$threads << Thread.new { start_level_of_the_day }
$threads << Thread.new { download_userlevel_scores } if (UPDATE_USERLEVELS || DO_EVERYTHING) && !DO_NOTHING
$threads << Thread.new { start_report }              if (REPORT_METANET    || DO_EVERYTHING) && !DO_NOTHING
$threads << Thread.new { start_userlevel_report }    if (REPORT_USERLEVELS || DO_EVERYTHING) && !DO_NOTHING

$bot.run(true)
puts "Established connection to servers: #{$bot.servers.map{ |id, s| s.name }.join(', ')}."
puts "Main channel: #{$channel.name}." if !$channel.nil?
puts "Mapping channel: #{$mapping_channel.name}." if !$mapping_channel.nil?

wd = Thread.new { watchdog }
wd.join
