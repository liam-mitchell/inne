require 'discordrb'
require 'json'
require 'net/http'
require 'thread'

API_BASE = 'https://discordapp.com/api'
TOKEN = 'Mjg5MTQxNzc2MjA2MjY2MzY5.C6IDyQ.1B1a2x_k7CF4UfaGWvhbGFVqdqM'
CLIENT_ID = 289141776206266369

$bot = Discordrb::Bot.new token: TOKEN, client_id: CLIENT_ID
$levels = []
$episodes = []
$seen = []
$channel = nil
$current = nil
$lock = Mutex.new

puts "the bot's URL is #{$bot.invite_url}"

def levels(eps = episodes)
  eps.product((0..4).to_a).map { |episode, level|
    episode + "-0" + level.to_s
  }
end

def episodes
  intro = ["SI"].product(["A", "B", "C", "D", "E"])
          .product((0..4).to_a)

  main = ["S", "SL"].product(["A", "B", "C", "D", "E", "X"])
         .product((0..19).to_a)

  (intro + main).map(&:flatten).map { |prefix, row, column|
    column = "0" + column.to_s if column < 10
    [prefix, row, column.to_s].join("-")
  }
end

def level_id(level)
  # id = episode_id(level) * 5
  # id += level["[0-9][0-9]$"].to_i
  # id
  # id = episode_id(level)
  # if level[/^S[IL]?/] != "SI"
  #   id -= 
  # end
  # TODO lol
  episode_id(level) * 5 + level[/[0-9][0-9]$/].to_i
end

def episode_id(episode)
  rows = {"SI": 5, "S": 6, "SL": 6}
  columns = {"SI": 5, "S": 20, "SL": 20}
  first_episodes = {"SI": 0, "S": 120, "SL": 240} # waat npp api

  prefix, row, column = episode.split("-")

  column = column.to_i

  id = first_episodes[prefix.to_sym]

  if row != "X"
    id += column * 5
  else
    id += column + 100
  end

  if row != "X"
    id += row.ord - "A".ord
  end

  id
end

def scores_uri(id, episode = false)
  URI("https://dojo.nplusplus.ninja/prod/steam/get_scores?steam_id=76561197992013087&steam_auth=&#{episode ? "episode" : "level"}_id=#{id}")
end

def scores(json)
  json["scores"].sort { |a, b| a["rank"] <=> b["rank"] }
    .each_with_index
    .map { |score, i| "#{i < 10 ? "0" : ""}#{i.to_s}: #{score["user_name"]} (#{score["score"] / 60.0})" }
    .join("\n\t")
end

def level_scores(level)
  uri = scores_uri(level_id(level))
  response = Net::HTTP.get(uri)

  if response == "-1337"
    return nil
  end

  return scores(JSON.parse(response))
end

def episode_scores(episode)
  uri = scores_uri(episode_id(episode), true)
  response = Net::HTTP.get(uri)

  if response == "-1337"
    return nil
  end

  return scores(JSON.parse(response))
end

def levelscores(event)
  level = event.content[/S[IL]?-[ABCDEX]-[0-9][0-9]-[0-9][0-9]/i]
  event << "getting scores for level #{level} (id #{level_id(level)})"
  event <<  "Level scores for #{level}:\n\t#{level_scores(level)}"
end

def episodescores(event)
  episode = event.content[/S[IL]?-[ABCDEX]-[0-9][0-9]/i]
  event << "getting scores for episode #{episode} (id #{episode_id(episode)})"
  event <<  "Episode scores for #{episode}:\n\t#{episode_scores(episode)}"
end

def next_level
  if $levels.length == 0
    return nil
  end

  $levels.delete_at(rand($levels.length))
end

def hello(event)
  if $channel.nil?
    $channel = event.channel
    $episodes = episodes
    $levels = levels($episodes)
  end

  event << "Hi!"
end

def level(event)
  event << "The current level of the day is #{$current}."
end

def dump(event)
  puts "episodes: \n\t#{$episodes.join("\n\t")}"
  puts "levels: \n\t#{$levels.join("\n\t")}"
  puts "current level: #{$current}"

  event << "I dumped some things to the log for you to look at."
end

$bot.mention do |event|
  hello(event) if event.content =~ /hello/i || event.content =~ /hi/i
  level(event) if event.content =~ /what.*level/i
  dump(event) if event.content =~ /dump/i
  episodescores(event) if event.content =~ /episode/
  levelscores(event) if event.content =~ /level/
end

def start
  now = Time.now
  tgt = now + 10

  while true
    sleep(tgt - now)

    now = tgt
    tgt += 10

    if $channel.nil?
      puts "not connected to a channel..."
      next
    end

    $lock.synchronize do
      $current = next_level
      $seen |= [$current]

      screenshot = "screenshots/#{$current}.jpg"

      $channel.send_message("Time for a new level of the day!")
      $channel.send_message("Level of the day: #{$current}")

      if File.exist? screenshot
        $channel.send_file(File::open(screenshot))
      else
        $channel.send_message("I don't have a screenshot for this one... :(")
      end

      $channel.send_message("Current high scores: \n\t#{level_scores($current)}")
    end
  end
end

threads = [
  # Thread.new { start },
  Thread.new { $bot.run }
]

threads.each do |t|
  t.join
end
