require 'discordrb'
require 'json'
require 'net/http'
require 'thread'
require 'yaml'
require_relative 'models.rb'
require_relative 'messages.rb'

require 'byebug'

TEST         = true # If set to true the bot will swith to the test one.
DOWNLOAD     = true # If set to false scores the score download threads won't fire up.
DATABASE_ENV = ENV['DATABASE_ENV'] || (TEST ? 'outte_test' : 'outte')
CONFIG       = YAML.load_file('db/config.yml')[DATABASE_ENV]

STATUS_UPDATE_FREQUENCY    = 5 * 60 # Redownload lotd scores, update bots status, etc, every 5 mins.
HIGHSCORE_UPDATE_FREQUENCY = 24 * 60 * 60 # daily
LEVEL_UPDATE_FREQUENCY     = CONFIG['level_update_frequency'] || 24 * 60 * 60 # daily
EPISODE_UPDATE_FREQUENCY   = CONFIG['episode_update_frequency'] || 7 * 24 * 60 * 60 # weekly
STORY_UPDATE_FREQUENCY     = CONFIG['story_update_frequency'] || 30 * 24 * 60 * 60 # monthly (roughly)

def log(msg)
  puts "[INFO] [#{Time.now}] #{msg}"
  open('LOG', 'a') { |f|
    f.puts "[INFO] [#{Time.now}] #{msg}"
  }
end

def err(msg)
  STDERR.puts "[ERROR] [#{Time.now}] #{msg}"
  open('LOG', 'a') { |f|
    f.puts "[ERROR] [#{Time.now}] #{msg}"
  }
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

# Periodically perform several useful tasks:
# - Update scores for lotd, eotw and cotm.
# - Update database with newest userlevels from all playing modes.
# - Update bot's status (it only lasts so much).
def update_status
  ActiveRecord::Base.establish_connection(CONFIG)

  while(true)
    get_current(Level).update_scores
    get_current(Episode).update_scores
    get_current(Story).update_scores
    (0..2).each{ |mode| Userlevel.browse(10, 0, mode, true) }
    $bot.update_status("online", "inne's evil cousin", nil, 0, false, 0)
    sleep(STATUS_UPDATE_FREQUENCY)
  end
rescue
  retry
end

def download_high_scores
  ActiveRecord::Base.establish_connection(CONFIG)

  begin
    while true
      log("updating high scores...")

      #Level.all.each(&:update_scores)
      #Episode.all.each(&:update_scores)
      #Story.all.each(&:update_scores)

      # We handle exceptions within each instance so that they don't force
      # a retry of the whole function.
      # Note: Exception handling inside do blocks requires ruby 2.5 or greater.
      [Level, Episode, Story].each do |type|
        type.all.each do |o|
          o.update_scores
        rescue => e
          err("error updating high scores for #{o.class.to_s.downcase} #{o.id.to_s}: #{e}")
          next
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
              score: r[1]
            }
          end

          ActiveRecord::Base.transaction do
            TotalScoreHistory.create(attrs)
          end
        end
      end

      next_score_update = get_next_update('score')
      # this will ensure that no matter what it says on the database, the correct time of next update is computed
      next_score_update -= HIGHSCORE_UPDATE_FREQUENCY while next_score_update > Time.now
      next_score_update += HIGHSCORE_UPDATE_FREQUENCY while next_score_update < Time.now
      delay = next_score_update - Time.now
      set_next_update('score', next_score_update)

      log("updated rankings, next score update in #{delay} seconds")

      sleep(delay) unless delay < 0
    end
  rescue => e
    err("error updating high scores: #{e}")
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
  log("starting level of the day...")
  ActiveRecord::Base.establish_connection(CONFIG)

  begin
    episode_day = false
    story_day = false
    while true
      # Autocorrect bad update times
      next_level_update = get_next_update(Level)
      next_level_update -= LEVEL_UPDATE_FREQUENCY while next_level_update > Time.now
      next_level_update += LEVEL_UPDATE_FREQUENCY while next_level_update < Time.now
      next_episode_update = get_next_update(Episode)
      next_episode_update -= EPISODE_UPDATE_FREQUENCY while next_episode_update > Time.now
      next_episode_update += EPISODE_UPDATE_FREQUENCY while next_episode_update < Time.now
      set_next_update(Level, next_level_update)
      set_next_update(Episode, next_episode_update)

      delay = next_level_update - Time.now
      sleep(delay) unless delay < 0
      next if !send_channel_next(Level)
      log("sent next level, next update at #{get_next_update(Level).to_s}")
      is_story_time = get_next_update(Story) < Time.now

      if Time.now > next_episode_update
        sleep(30) # let discord catch up
        send_channel_next(Episode)
        episode_day = true
        log("sent next episode, next update at #{get_next_update(Episode).to_s}")
      end
      if is_story_time
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
$channel = nil

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

if DOWNLOAD
  $threads = [
    Thread.new { start_level_of_the_day },
    Thread.new { download_high_scores },
    Thread.new { update_status }
  ]
end


$bot.run(true)

wd = Thread.new { watchdog }
wd.join
