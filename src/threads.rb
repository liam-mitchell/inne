# This file contains all the functions that get executed in the background,
# because they perform periodic tasks like updating the database scores,
# publishing the lotd, etc.
#
# See the TASK VARIABLES in src/constants.rb for configuration. Also, see the
# end of src/inne++.rb for the joining thread.

require_relative 'constants.rb'
require_relative 'utils.rb'
require_relative 'models.rb'

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
      GlobalProperty.get_current(Level).update_scores
      GlobalProperty.get_current(Episode).update_scores
      GlobalProperty.get_current(Story).update_scores
    end
    $bot.update_status("online", "inne's evil cousin", nil, 0, false, 0)  
    sleep(STATUS_UPDATE_FREQUENCY)
  end
rescue
  retry
end

# Check for new Twitch streams, and send notices.
def update_twitch
  if $content_channel.nil?
    err("not connected to a channel, not sending twitch report")
    raise
  end
  if $twitch_token.nil?
    $twitch_token = Twitch::get_twitch_token
    Twitch::update_twitch_streams
  end
  while(true)
    sleep(WAIT)
    Twitch::update_twitch_streams
    Twitch::new_streams.each{ |game, list|
      list.each{ |stream|
        Twitch::post_stream(stream)
      }
    }
    sleep(TWITCH_UPDATE_FREQUENCY)
  end
rescue => e
  err(e)
  sleep(WAIT)
  retry
end

# Update missing demos (e.g., if they failed to download originally)
def download_demos
  log("updating demos...")
  archives = Archive.where(lost: false)
                    .joins("LEFT JOIN demos ON demos.id = archives.id")
                    .where("demos.demo IS NULL")
                    .pluck(:id, :replay_id, :highscoreable_type)
  archives.each_with_index do |ar, i|
    attempts ||= 0
    Demo.find_or_create_by(id: ar[0]).update_demo
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

# Driver for the function above
def start_demos
  while true
    sleep(WAIT) # prevent crazy loops
    next_demo_update = correct_time(GlobalProperty.get_next_update('demo'), DEMO_UPDATE_FREQUENCY)
    GlobalProperty.set_next_update('demo', next_demo_update)
    delay = next_demo_update - Time.now
    sleep(delay) unless delay < 0
    next if !download_demos
  end
rescue => e
  err("error updating demos: #{e}")
  retry
end

# Compute and send the weekly highscoring report and the daily summary
def send_report
  log("sending highscoring report...")
  if $channel.nil?
    err("not connected to a channel, not sending highscoring report")
    return false
  end

  base  = Time.new(2020, 9, 3, 0, 0, 0, "+00:00").to_i # when archiving begun
  time  = [Time.now.to_i - REPORT_UPDATE_SIZE,  base].max
  time2 = [Time.now.to_i - SUMMARY_UPDATE_SIZE, base].max
  now   = Time.now.to_i
  pad   = [2, DEFAULT_PADDING, 6, 6, 6, 5, 4]
  log   = [] if LOG_REPORT

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

  $channel.send_message("**Weekly highscoring report**:```#{header}\n#{sep}\n#{changes}```")
  if LOG_REPORT
    log_text = log.sort_by{ |name, scores| name }.map{ |name, scores|
      scores.map{ |s|
        name[0..14].ljust(15, " ") + " " + (s[1] == 20 ? " x  " : s[1].ordinalize).rjust(4, "0") + "->" + s[2].ordinalize.rjust(4, "0") + " " + s[3].name.ljust(10, " ") + " " + ("%.3f" % (s[4].to_f / 60.0))
      }.join("\n")
    }.join("\n")
    File.write("../report_log", log_text)
  end

  sleep(1)
  # Compute, for levels, episodes and stories, the following quantities:
  # Seconds of total score gained.
  # Seconds of total score in 19th gained.
  # Total number of changes.
  # Total number of involved players.
  # Total number of involved highscoreables.
  total = { "Level" => [0, 0, 0, 0, 0], "Episode" => [0, 0, 0, 0, 0], "Story" => [0, 0, 0, 0, 0] }
  changes = Archive.where("unix_timestamp(date) > #{time2}")
                   .order('date desc')
                   .map{ |ar|
                     total[ar.highscoreable.class.to_s][2] += 1
                     [ar.metanet_id, ar.highscoreable]
                   }
  changes.group_by{ |s| s[1].class.to_s }
         .each{ |klass, scores|
                total[klass][3] = scores.uniq{ |s| s[0]    }.size
                total[klass][4] = scores.uniq{ |s| s[1].id }.size
              }
  changes.map{ |h| h[1] }
         .uniq
         .each{ |h|
                total[h.class.to_s][0] += Archive.scores(h, now).first[1] - Archive.scores(h, time).first[1]
                total[h.class.to_s][1] += Archive.scores(h, now).last[1] - Archive.scores(h, time).last[1]
              }

  total = total.map{ |klass, n|
    "• There were **#{n[2]}** new scores by **#{n[3]}** players in **#{n[4]}** #{klass.downcase.pluralize}, making the boards **#{"%.3f" % [n[1].to_f / 60.0]}** seconds harder and increasing the total 0th score by **#{"%.3f" % [n[0].to_f / 60.0]}** seconds."
  }.join("\n")
  $channel.send_message("**Daily highscoring summary**:\n" + total)

  log("highscoring report sent")  
  return true
end

# Driver for the function above
def start_report
  begin
    if TEST && TEST_REPORT
      raise if !send_report
    else
      while true
        sleep(WAIT)
        next_report_update = correct_time(GlobalProperty.get_next_update('report'), REPORT_UPDATE_FREQUENCY)
        GlobalProperty.set_next_update('report', next_report_update)
        delay = next_report_update - Time.now
        sleep(delay) unless delay < 0
        next if !send_report
      end
    end
  rescue => e
    err("error sending highscoring report: #{e}")
    sleep(WAIT)
    retry
  end
end

# Compute and send the daily userlevel highscoring report for the newest
# 500 userlevels.
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

# Driver for the function above
def start_userlevel_report
  begin
    while true
      sleep(WAIT)
      next_userlevel_report_update = correct_time(GlobalProperty.get_next_update('userlevel_report'), USERLEVEL_REPORT_FREQUENCY)
      GlobalProperty.set_next_update('userlevel_report', next_userlevel_report_update)
      delay = next_userlevel_report_update - Time.now
      sleep(delay) unless delay < 0
      next if !send_userlevel_report
    end
  rescue => e
    err("error sending userlevel highscoring report: #{e}")
    retry
  end
end

# Update database scores for Metanet Solo levels, episodes and stories
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

# Driver for the function above
def start_high_scores
  begin
    while true
      sleep(WAIT)
      next_score_update = correct_time(GlobalProperty.get_next_update('score'), HIGHSCORE_UPDATE_FREQUENCY)
      GlobalProperty.set_next_update('score', next_score_update)
      delay = next_score_update - Time.now
      sleep(delay) unless delay < 0
      next if !download_high_scores
    end
  rescue => e
    err("error updating high scores: #{e}")
    retry
  end
end

# Compute and store a bunch of different rankings daily, so that we can build
# histories later.
#
# NOTE: Histories this way, stored in bulk in the database, are deprecated.
# We now using a differential table with all new scores, called 'archives'.
# So we can rebuild the boards at any given point in time with precision.
# Therefore, this function is not being used anymore.
def update_histories
  log("updating histories...")
  now = Time.now
  [:SI, :S, :SL, :SS, :SU, :SS2].each do |tab|
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

# Driver for the function above, which is not used anymore (see comment there)
def start_histories
  while true
    sleep(WAIT)
    next_history_update = correct_time(GlobalProperty.get_next_update('history'), HISTORY_UPDATE_FREQUENCY)
    GlobalProperty.set_next_update('history', next_history_update)
    delay = next_history_update - Time.now
    sleep(delay) unless delay < 0
    next if !update_histories
  end
rescue => e
  err("error updating highscore histories: #{e}")
  retry
end

# Precompute and store several useful userlevel rankings daily, so that we
# can check the history later. Since we don't have a differential table here,
# like for Metanet levels, this function is NOT deprecated.
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

# Driver for the function above
def start_userlevel_histories
  while true
    sleep(WAIT)
    next_userlevel_history_update = correct_time(GlobalProperty.get_next_update('userlevel_history'), USERLEVEL_HISTORY_FREQUENCY)
    GlobalProperty.set_next_update('userlevel_history', next_userlevel_history_update)
    delay = next_userlevel_history_update - Time.now
    sleep(delay) unless delay < 0
    next if !update_userlevel_histories
  end
rescue => e
  err("error updating userlevel highscore histories: #{e}")
  retry
end

# Download the scores for the scores for the latest 500 userlevels, for use in
# the daily userlevel highscoring rankings.
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

# Driver for the function above
def start_userlevel_scores
  while true
    sleep(WAIT)
    next_userlevel_score_update = correct_time(GlobalProperty.get_next_update('userlevel_score'), USERLEVEL_SCORE_FREQUENCY)
    GlobalProperty.set_next_update('userlevel_score', next_userlevel_score_update)
    delay = next_userlevel_score_update - Time.now
    sleep(delay) unless delay < 0
    next if !download_userlevel_scores
  end
rescue => e
  err("error downloading userlevel highscores: #{e}")
  retry
end

# Continuously, but more slowly, download the scores for ALL userlevels, to keep
# the database scores reasonably up to date.
# We select the userlevels to update in reverse order of last update, i.e., we
# always update the ones which haven't been updated the longest.
def update_all_userlevels_chunk
  log("updating next userlevel chunk scores...")
  Userlevel.where(mode: :solo).order('score_update IS NOT NULL, score_update').take(USERLEVEL_DOWNLOAD_CHUNK).each do |u|
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

# Driver for the function above
def update_all_userlevels
  log("updating all userlevel scores...")
  while true
    sleep(WAIT)
    update_all_userlevels_chunk
  end
rescue => e
  err("error updating all userlevel scores: #{e}")
  retry
end

# Download some userlevel tabs (best, top weekly, featured, hardest), for all
# 3 modes, to keep those lists up to date in the database
def update_userlevel_tabs
  log("updating userlevel tabs")
  ["solo", "coop", "race"].each_with_index{ |mode, m|
    [7, 8, 9, 11].each { |qt|
      tab = USERLEVEL_TABS[qt][:name]
      page = -1
      while true
        page += 1
        break if !Userlevel::update_relationships(qt, page, m)
      end
      if USERLEVEL_TABS[qt][:size] != -1
        ActiveRecord::Base.transaction do
          UserlevelTab.where(mode: m, qt: qt).where("`index` >= #{USERLEVEL_TABS[qt][:size]}").delete_all
        end
      end
    }
  }
  print(" " * 80 + "\r")
  log("updated userlevel tabs")
  return true   
rescue => e
  err("error updating userlevel tabs: #{e}")
  return false
end

# Driver for the function above
def start_userlevel_tabs
  while true
    sleep(WAIT)
    next_userlevel_tab_update = correct_time(GlobalProperty.get_next_update('userlevel_tab'), USERLEVEL_TAB_FREQUENCY)
    GlobalProperty.set_next_update('userlevel_tab', next_userlevel_tab_update)
    delay = next_userlevel_tab_update - Time.now
    sleep(delay) unless delay < 0
    next if !update_userlevel_tabs
  end
rescue => e
  err("error updating userlevel tabs: #{e}")
  retry
end

############ LOTD FUNCTIONS ############

# Special screenshot function, used for lotd/eotw/cotm.
# The one that users can call is in src/messages.rb
def send_channel_screenshot(name, caption)
  name = name.gsub(/\?/, 'SS').gsub(/!/, 'SS2')
  screenshot = "screenshots/#{name}.jpg"
  if File.exist? screenshot
    $channel.send_file(File::open(screenshot), caption: caption)
  else
    $channel.send_message(caption + "\nI don't have a screenshot for this one... :(")
  end
end

# Send the score differences in the old lotd/eotw/cotm
def send_channel_diff(level, old_scores, since)
  return if level.nil? || old_scores.nil?

  diff = level.format_difference(old_scores)
  $channel.send_message("Score changes on #{level.format_name} since #{since}:\n```#{diff}```")
end

# Daily reminders for eotw and cotm
def send_channel_reminder
  $channel.send_message("Also, remember that the current episode of the week is #{GlobalProperty.get_current(Episode).format_name}.")
end

def send_channel_story_reminder
  $channel.send_message("Also, remember that the current column of the month is #{GlobalProperty.get_current(Story).format_name}.")
end

# Publish the lotd/eotw/cotm
# This function also updates the scores of said board, and of the new one
def send_channel_next(type)
  log("sending next #{type.to_s.downcase}")
  if $channel.nil?
    err("not connected to a channel, not sending level of the day")
    return false
  end

  last = GlobalProperty.get_current(type)
  current = GlobalProperty.get_next(type)
  GlobalProperty.set_current(type, current)

  if current.nil?
    err("no more #{type.to_s.downcase}")
    return false
  end

  if !OFFLINE_STRICT && UPDATE_SCORES_ON_LOTD
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
    send_channel_diff(last, GlobalProperty.get_saved_scores(type), since)
  else
    $channel.send_message("Strict offline mode activated, not sending score differences.")
  end
  GlobalProperty.set_saved_scores(type, current)

  return true
end

# Driver for the function above (takes care of timing, db update, etc)
def start_level_of_the_day
  begin
    episode_day = false
    story_day = false
    while true
      next_level_update = correct_time(GlobalProperty.get_next_update(Level), LEVEL_UPDATE_FREQUENCY)
      next_episode_update = correct_time(GlobalProperty.get_next_update(Episode), EPISODE_UPDATE_FREQUENCY)
      GlobalProperty.set_next_update(Level, next_level_update)
      GlobalProperty.set_next_update(Episode, next_episode_update)
      delay = next_level_update - Time.now
      sleep(delay) unless delay < 0

     if (UPDATE_LEVEL || DO_EVERYTHING) && !DO_NOTHING
        log("starting level of the day...")
        next if !send_channel_next(Level)
        log("sent next level, next update at #{GlobalProperty.get_next_update(Level).to_s}")
      end

      if (UPDATE_EPISODE || DO_EVERYTHING) && !DO_NOTHING && next_episode_update < Time.now
        sleep(30) # let discord catch up
        send_channel_next(Episode)
        episode_day = true
        log("sent next episode, next update at #{GlobalProperty.get_next_update(Episode).to_s}")
      end

      if (UPDATE_STORY || DO_EVERYTHING) && !DO_NOTHING && GlobalProperty.get_next_update(Story) < Time.now
        # we add days until we get to the first day of the next month
        next_story_update = GlobalProperty.get_next_update(Story)
        month = next_story_update.month
        next_story_update += LEVEL_UPDATE_FREQUENCY while next_story_update.month == month
        GlobalProperty.set_next_update(Story, next_story_update)
        sleep(30) # let discord catch up
        send_channel_next(Story)
        story_day = true
        log("sent next story, next update at #{GlobalProperty.get_next_update(Story).to_s}")
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

# Start all the tasks in this file in independent threads
def start_threads
  $threads = []
  $threads << Thread.new { update_status }             if (UPDATE_STATUS     || DO_EVERYTHING) && !DO_NOTHING
  $threads << Thread.new { update_twitch }             if (UPDATE_TWITCH     || DO_EVERYTHING) && !DO_NOTHING
  $threads << Thread.new { start_high_scores }         if (UPDATE_SCORES     || DO_EVERYTHING) && !DO_NOTHING && !OFFLINE_MODE
  $threads << Thread.new { start_demos }               if (UPDATE_DEMOS      || DO_EVERYTHING) && !DO_NOTHING && !OFFLINE_MODE
  $threads << Thread.new { start_level_of_the_day }    # No checks here because they're done individually there
  $threads << Thread.new { start_userlevel_scores }    if (UPDATE_USERLEVELS || DO_EVERYTHING) && !DO_NOTHING && !OFFLINE_MODE
  $threads << Thread.new { update_all_userlevels }     if (UPDATE_USER_GLOB  || DO_EVERYTHING) && !DO_NOTHING && !OFFLINE_MODE
  $threads << Thread.new { start_userlevel_histories } if (UPDATE_USER_HIST  || DO_EVERYTHING) && !DO_NOTHING && !OFFLINE_MODE
  $threads << Thread.new { start_userlevel_tabs }      if (UPDATE_USER_TABS  || DO_EVERYTHING) && !DO_NOTHING && !OFFLINE_MODE
  $threads << Thread.new { start_report }              if (REPORT_METANET    || DO_EVERYTHING) && !DO_NOTHING && !OFFLINE_MODE
  $threads << Thread.new { start_userlevel_report }    if (REPORT_USERLEVELS || DO_EVERYTHING) && !DO_NOTHING && !OFFLINE_MODE
  $threads << Thread.new { potato }                    if POTATO && !DO_NOTHING
  #$threads << Thread.new { Cuse::on }                  if SOCKET && CUSE_SOCKET && !DO_NOTHING
  $threads << Thread.new { Cle::on }                   if SOCKET && CLE_SOCKET && !DO_NOTHING
  $threads << Thread.new { sleep }
end

def block_threads
  $threads.last.join
end

def unblock_threads
  $threads.last.run
  log("Shut down")
end