require 'active_record'
require 'net/http'
require_relative 'constants.rb'
require_relative 'utils.rb'

module HighScore

  # Overwrite Rails default definition to sort by rank (rather than ID)
  #def scores
  #  scores.sort_by{ |s| s.rank }
  #end

  def self.format_rank(rank)
    "#{rank < 10 ? '0' : ''}#{rank}"
  end

  # everything in the "spreads" and "ties" functions has been carefully
  # benchmarked so, though unelegant, it's the most efficient set of
  # sql queries
  def self.spreads(n, type, tabs, small = false, player_id = nil)
    n = n.clamp(0,19)
    type = ensure_type(type)
    bench(:start) if BENCHMARK
    # retrieve player's 0ths if necessary
    if !player_id.nil?
      ids = Score.where(highscoreable_type: type.to_s, rank: 0, player_id: player_id)
      ids = ids.where(tab: tabs) if !tabs.empty?
      ids = ids.pluck('highscoreable_id')
    end
    # retrieve required scores and compute spreads
    ret1 = Score.where(highscoreable_type: type.to_s, rank: 0)
    ret1 = ret1.where(tab: tabs) if !tabs.empty?
    ret1 = ret1.where(highscoreable_id: ids) if !player_id.nil?
    ret1 = ret1.pluck(:highscoreable_id, :score).to_h
    ret2 = Score.where(highscoreable_type: type.to_s, rank: n)
    ret2 = ret2.where(tab: tabs) if !tabs.empty?
    ret2 = ret2.where(highscoreable_id: ids) if !player_id.nil?
    ret2 = ret2.pluck(:highscoreable_id, :score).to_h
    ret = ret2.map{ |id, s| [id, ret1[id] - s] }
              .sort_by{ |id, s| small ? s : -s }
              .take(NUM_ENTRIES)
              .to_h
    # retrieve level names
    lnames = type.where(id: ret.keys)
                 .pluck(:id, :name)
                 .to_h
    # retrieve player names
    pnames = Score.where(highscoreable_type: type.to_s, highscoreable_id: ret.keys, rank: 0)
                  .joins("INNER JOIN players ON players.id = scores.player_id")
                  .pluck('scores.highscoreable_id', 'players.name', 'players.display_name')
                  .map{ |a, b, c| [a, [b, c]] }
                  .to_h
    ret = ret.map{ |id, s| [lnames[id], s, pnames[id][1].nil? ? pnames[id][0] : pnames[id][1]] }
    bench(:step) if BENCHMARK
    ret
  end

  # @par player_id: Exclude levels where the player already has a score
  # @par maxed:     Sort differently depending on whether we're interested in maxed or maxable
  # @par rank:      Return rankings of people with most scores in maxed / maxable levels
  def self.ties(type, tabs, player_id = nil, maxed = nil, rank = false)
    type = ensure_type(type)
    bench(:start) if BENCHMARK
    # retrieve most tied for 0th levels
    ret = Score.where(highscoreable_type: type.to_s, tied_rank: 0)
    ret = ret.where(tab: tabs) if !tabs.empty?
    ret = ret.group(:highscoreable_id)
             .order(!maxed ? 'count(id) desc' : '', :highscoreable_id)
             .having("count(id) >= #{MIN_TIES}")
             .having(!player_id.nil? ? 'amount = 0' : '')
             .pluck('highscoreable_id', 'count(id)', !player_id.nil? ? "count(if(player_id = #{player_id}, player_id, NULL)) AS amount" : '1')
             .map{ |s| s[0..1] }
             .to_h
    # retrieve total score counts for each level (to compare against the tie count and determine maxes)
    counts = Score.where(highscoreable_type: type.to_s, highscoreable_id: ret.keys)
                  .group(:highscoreable_id)
                  .order('count(id) desc')
                  .count(:id)
    # filter
    maxed ? ret.select!{ |id, c| c == counts[id] } : ret.select!{ |id, c| c < counts[id] } if !maxed.nil?

    if rank
      ret = ret.keys
    else
      # retrieve player names owning the 0ths on said level
      pnames = Score.where(highscoreable_type: type.to_s, highscoreable_id: ret.keys, rank: 0)
                    .joins("INNER JOIN players ON players.id = scores.player_id")
                    .pluck('scores.highscoreable_id', 'players.name', 'players.display_name')
                    .map{ |a, b, c| [a, [b, c]] }
                    .to_h
      # retrieve level names
      lnames = type.where(id: ret.keys)
                   .pluck(:id, :name)
                   .to_h
      ret = ret.map{ |id, c| [lnames[id], c, counts[id], pnames[id][1].nil? ? pnames[id][0] : pnames[id][1]] }
    end
    bench(:step) if BENCHMARK
    ret
  end

  def scores_uri(steam_id)
    klass = self.class == Userlevel ? "level" : self.class.to_s.downcase
    URI.parse("https://dojo.nplusplus.ninja/prod/steam/get_scores?steam_id=#{steam_id}&steam_auth=&#{klass}_id=#{self.id.to_s}")
  end

  def replay_uri(steam_id, replay_id)
    qt = [Level, Userlevel].include?(self.class) ? 0 : (self.class == Episode ? 1 : 4)
    URI.parse("https://dojo.nplusplus.ninja/prod/steam/get_replay?steam_id=#{steam_id}&steam_auth=&replay_id=#{replay_id}&qt=#{qt}")
  end

  def self.get_data(uri_proc, data_proc, err, *vargs)
    attempts ||= 0
    initial_id = get_last_steam_id
    response = Net::HTTP.get_response(uri_proc.call(initial_id, *vargs))
    while response.body == INVALID_RESP
      deactivate_last_steam_id
      update_last_steam_id
      break if get_last_steam_id == initial_id
      response = Net::HTTP.get_response(uri_proc.call(get_last_steam_id))
    end
    return nil if response.body == INVALID_RESP
    raise "502 Bad Gateway" if response.code.to_i == 502
    activate_last_steam_id
    data_proc.call(response.body)
  rescue => e
    if (attempts += 1) < RETRIES
      if SHOW_ERRORS
        err("#{err}: #{e}")
      end
      retry
    else
      return nil
    end
  end

  def get_scores
    uri  = Proc.new { |steam_id| scores_uri(steam_id) }
    data = Proc.new { |data| correct_ties(clean_scores(JSON.parse(data)['scores'])) }
    err  = "error getting scores for #{self.class.to_s.downcase} with id #{self.id.to_s}"
    HighScore::get_data(uri, data, err)
  end

  def get_replay(replay_id)
    uri  = Proc.new { |steam_id| replay_uri(steam_id, replay_id) }
    data = Proc.new { |data| data }
    err  = "error getting replay with id #{replay_id} for #{self.class.to_s.downcase} with id #{self.id.to_s}"
    HighScore::get_data(uri, data, err)
  end

  # Remove hackers and cheaters both by implementing the ignore lists and the score thresholds.
  def clean_scores(boards)
    # Remove potential duplicates
    # Edit: Commented because now we're storing Metanet IDs, names can repeat
    #boards.uniq!{ |s| s['user_name'] }

    # Compute score upper limit
    if self.class == Userlevel
      limit = 2 ** 32 - 1 # No limit
    else
      limit = TABS[self.class.to_s].map{ |k, v| v[1] }.max
      TABS[self.class.to_s].each{ |k, v| if v[0].include?(self.id) then limit = v[1]; break end  }
    end

    # Filter out cheated/hacked runs, or accidentally incorrect scores
    k = self.class.to_s.downcase.to_sym
    boards.reject!{ |s|
      IGNORED_PLAYERS.include?(s['user_name']) || IGNORED_IDS.include?(s['user_id']) || PATCH_IND_DEL[k].include?(s['replay_id']) || s['score'] / 1000.0 >= limit
    }

    # Batch patch old incorrect runs
    if PATCH_RUNS[k].key?(self.id)
      boards.each{ |s|
        entry = PATCH_RUNS[k][self.id]
        s['score'] += 1000 * entry[1] if s['replay_id'] <= entry[0]
      }
    end

    # Individually patch old incorrect runs
    boards.each{ |s|
      s['score'] += 1000 * PATCH_IND_CHG[k][s['replay_id']] if PATCH_IND_CHG[k].key?(s['replay_id'])
    }

    boards
  rescue
    boards
  end

  def save_scores(updated)
    ActiveRecord::Base.transaction do
      updated.each_with_index do |score, i|
        # Compute values, userlevels have some differences
        player = (self.class == Userlevel ? UserlevelPlayer : Player).find_or_create_by(metanet_id: score['user_id'])
        player.update(name: score['user_name'].force_encoding('UTF-8'))
        scoretime = score['score'] / 1000.0
        scoretime = (scoretime * 60.0).round if self.class == Userlevel
        # Update common values
        scores.find_or_create_by(rank: i).update(
          score:     scoretime,
          replay_id: score['replay_id'].to_i,
          player:    player,
          tied_rank: updated.find_index { |s| s['score'] == score['score'] }
        )
        # Updates for non-userlevels (tab, archive, demos)
        scores.find_by(rank: i).update(tab: self.tab) if self.class != Userlevel
        # Update the archive if the run is new
        if self.class != Userlevel && Archive.find_by(replay_id: score['replay_id'], highscoreable_type: self.class.to_s).nil?
          # Update archive entry
          ar = Archive.create(
            replay_id:     score['replay_id'].to_i,
            player:        Player.find_by(metanet_id: score['user_id']),
            highscoreable: self,
            score:         (score['score'] * 60.0 / 1000.0).round,
            metanet_id:    score['user_id'].to_i, # future-proof the db
            date:          Time.now,
            tab:           self.tab
          )
          # Update demo entry
          demo = Demo.find_or_create_by(id: ar.id)
          demo.update(replay_id: ar.replay_id, htype: Demo.htypes[ar.highscoreable_type.to_s.downcase])
          demo.update_demo
        end
      end
      # Userlevel-specific
      self.update(last_update: Time.now) if self.class == Userlevel
      self.update(scored:      true)     if self.class == Userlevel && updated.size > 0
      # Update coolness and star attributes
      scores.where("rank < #{find_coolness}").update_all(cool: true)
      scores.find_by(rank: 0).update(star: true)
      # Remove scores stuck at the bottom after ignoring cheaters
      scores.where(rank: (updated.size..19).to_a).delete_all
    end
  end

  def update_scores
    updated = get_scores

    if updated.nil?
      if SHOW_ERRORS
        # TODO make this use err()
        STDERR.puts "[WARNING] [#{Time.now}] failed to retrieve scores from #{scores_uri(get_last_steam_id)}"
      end
      return -1
    end

    save_scores(updated)
  rescue => e
    if SHOW_ERRORS
      err("error updating database with level #{self.id.to_s}: #{e}")
    end
    return -1
  end

  def get_replay_info(rank)
    updated = get_scores

    if updated.nil?
      if SHOW_ERRORS
        # TODO make this use err()
        STDERR.puts "[WARNING] [#{Time.now}] failed to retrieve replay info from #{scores_uri(get_last_steam_id)}"
      end
      return
    end

    updated.select { |score| !IGNORED_PLAYERS.include?(score['user_name']) }.uniq { |score| score['user_name'] }[rank]
  end

  def analyze_replay(replay_id)
    replay = get_replay(replay_id)
    demo = Zlib::Inflate.inflate(replay[16..-1])[30..-1]
    analysis = demo.unpack('H*')[0].scan(/../).map{ |b| b.to_i }[1..-1]
  end

  def correct_ties(score_hash)
    score_hash.sort_by{ |s| [-s['score'], s['replay_id']] }
  end

  def max_name_length
    scores.map{ |s| s.player.name.length }.max
  end

  def find_coolness
    max   = scores.map(&:score).max.to_i.to_s.length + 4
    s1    = scores.first.score.to_s
    s2    = scores.last.score.to_s
    d     = (0...max).find{ |i| s1[i] != s2[i] }
    if !d.nil?
      d     = -(max - d - 5) - (max - d < 4 ? 1 : 0)
      cools = scores.size.times.find{ |i| scores[i].score < s1.to_f.truncate(d) }
    else
      cools = 0
    end
    cools
  rescue => e
    puts e.backtrace
    raise
  end

  def format_scores(padding = max_name_length)
    max = scores.map(&:score).max.to_i.to_s.length + 4
    scores.each_with_index.map{ |s, i| s.format(padding, max) }.join("\n")
  end

  def difference(old)
    scores.map do |score|
      oldscore = old.find { |o| o['player']['name'] == score.player.name }
      change = nil

      if oldscore
        change = {rank: oldscore['rank'] - score.rank, score: score.score - oldscore['score']}
      end

      {score: score, change: change}
    end
  end

  def format_difference(old)
    diffs = difference(old)

    name_padding = scores.map{ |s| s.player.name.length }.max
    score_padding = scores.map{ |s| s.score.to_i }.max.to_s.length + 4
    rank_padding = diffs.map{ |d| d[:change] }.compact.map{ |d| d[:rank].to_i }.max.to_s.length
    change_padding = diffs.map{ |d| d[:change] }.compact.map{ |d| d[:score].to_i }.max.to_s.length + 4

    difference(old).map { |o|
      c = o[:change]
      diff = c ? "#{"++-"[c[:rank] <=> 0]}#{"%#{rank_padding}d" % [c[:rank].abs]}, +#{"%#{change_padding}.3f" % [c[:score]]}" : "new"
      "#{o[:score].format(name_padding, score_padding, false)} (#{diff})"
    }.join("\n")
  end

  # The next function navigates through highscoreables.
  # @par1: Offset (1 = next, -1 = prev, 2 = next tab, -2 = prev tab).
  #
  # Note:
  #   We deal with edge cases separately because we change the natural order
  #   of tabs, so the ID is not always what we want (the internal order of
  #   tabs is SI, S, SL, ?, SU, !, but we want SI, S, SU, SL, ?, !, as it
  #   appears in the game).
  def nav(c)
    tabs    = self.class.to_s == "Level" ? 6 : 4
    ids     = [:SI, :S, :SU, :SL, :SS, :SS2][0.. tabs - 1].map{ |t| [ TABS[self.class.to_s][t][0][0], TABS[self.class.to_s][t][0][-1] ] }
    new_id  = nil
    new_id2 = nil

    ids.each_with_index{ |t, i|
      case c
      when 1
        new_id  = ids[(i + 1) % tabs][0] if self.id == t[1]
        new_id2 = self.class.where("id > #{self.id}").pluck("MIN(id)").first.to_i
      when -1
        new_id  = ids[(i - 1) % tabs][1] if self.id == t[0]
        new_id2 = self.class.where("id < #{self.id}").pluck("MAX(id)").first.to_i
      when 2
        new_id = ids[(i + 1) % tabs][0] if self.id >= t[0] && self.id <= t[1]
      when -2
        new_id = ids[(i - 1) % tabs][0] if self.id >= t[0] && self.id <= t[1]
      else
        new_id = self.id
      end
    }
    self.class.find(new_id || new_id2)
  rescue
    self
  end

  # Shorcuts for the above
  def next_h
    nav(1)
  end

  def prev_h
    nav(-1)
  end

  def next_t
    nav(2)
  end

  def prev_t
    nav(-2)
  end
end

class Level < ActiveRecord::Base
  include HighScore
  has_many :scores, as: :highscoreable
  has_many :videos, as: :highscoreable
  has_many :challenges
  has_many :level_aliases
  belongs_to :episode
  enum tab: [:SI, :S, :SU, :SL, :SS, :SS2]

  def add_alias(a)
    LevelAlias.find_or_create_by(level: self, alias: a)
  end

  def format_name
    "#{longname} (#{name})"
  end

  def format_challenges
    pad = challenges.map{ |c| c.count }.max
    challenges.map{ |c| c.format(pad) }.join("\n")
  end
end

class Episode < ActiveRecord::Base
  include HighScore
  has_many :scores, as: :highscoreable
  has_many :videos, as: :highscoreable
  has_many :levels
  enum tab: [:SI, :S, :SU, :SL, :SS, :SS2]

  def self.cleanliness(tabs, rank = 0)
    bench(:start) if BENCHMARK
    query = !tabs.empty? ? Score.where(tab: tabs) : Score
    # retrieve level 0th sums
    lvls = query.where(highscoreable_type: 'Level', rank: 0)
                .joins('INNER JOIN levels ON levels.id = scores.highscoreable_id')
                .group('levels.episode_id')
                .sum(:score)
    # retrieve episode names
    epis = self.pluck(:id, :name).to_h
    # retrieve episode 0th scores
    ret = query.where(highscoreable_type: 'Episode', rank: 0)
               .joins('INNER JOIN episodes ON episodes.id = scores.highscoreable_id')
               .joins('INNER JOIN players ON players.id = scores.player_id')
               .pluck('episodes.id', 'scores.score', 'players.name')
               .map{ |e, s, n| [epis[e], round_score(lvls[e] - s - 360), n] }
    bench(:step) if BENCHMARK
    ret
  end

  def self.ownages(tabs)
    bench(:start) if BENCHMARK
    query = !tabs.empty? ? Score.where(tab: tabs) : Score
    # retrieve episodes with all 5 levels owned by the same person
    epis = query.where(highscoreable_type: 'Level', rank: 0)
                .joins('INNER JOIN levels ON levels.id = scores.highscoreable_id')
                .group('levels.episode_id')
                .having('cnt = 1')
                .pluck('levels.episode_id', 'MIN(scores.player_id)', 'COUNT(DISTINCT scores.player_id) AS cnt')
                .map{ |e, p, c| [e, p] }
                .to_h
    # retrieve respective episode 0ths
    zeroes = query.where(highscoreable_type: 'Episode', highscoreable_id: epis.keys, rank: 0)
                  .joins('INNER JOIN players ON players.id = scores.player_id')
                  .pluck('scores.highscoreable_id', 'players.id')
                  .to_h
    # retrieve episode names
    enames = Episode.where(id: epis.keys)
                    .pluck(:id, :name)
                    .to_h
    # retrieve player names
    pnames = Player.where(id: epis.values)
                   .pluck(:id, :name, :display_name)
                   .map{ |a, b, c| [a, [b, c]] }
                   .to_h
    # keep only matches between the previous 2 result sets to obtain true ownages
    ret = epis.reject{ |e, p| p != zeroes[e] }
              .sort_by{ |e, p| e }
              .map{ |e, p| [enames[e], pnames[p][1].nil? ? pnames[p][0] : pnames[p][1]] }
    bench(:step) if BENCHMARK
    ret
  end

  def format_name
    "#{name}"
  end

  def cleanliness(rank = 0)
    bench(:start) if BENCHMARK
    ret = [name, Score.where(highscoreable: levels, rank: 0).sum(:score) - scores[rank].score - 360, scores[rank].player.name]
    bench(:step) if BENCHMARK
    ret
  end

  def ownage
    bench(:start) if BENCHMARK
    owner = scores[0].player
    lvls = Score.where(highscoreable: levels, rank: 0)
                .joins('INNER JOIN players ON players.id = scores.player_id')
                .count("if(players.id = #{owner.id}, 1, NULL)")
    ret = [name, lvls == 5, owner.name]
    bench(:step) if BENCHMARK
    ret
  end

  def splits(rank = 0)
    acc = 90
    Level.where("UPPER(name) LIKE ?", name.upcase + '%').map{ |l| acc += l.scores[rank].score - 90 }
  rescue
    nil
  end
end

class Story < ActiveRecord::Base
  include HighScore
  has_many :scores, as: :highscoreable
  has_many :videos, as: :highscoreable
  enum tab: [:SI, :S, :SU, :SL, :SS, :SS2]

  def format_name
    "#{name}"
  end
end

class Score < ActiveRecord::Base
  belongs_to :player
  belongs_to :highscoreable, polymorphic: true
  belongs_to :level,   -> { where(scores: {highscoreable_type: 'Level'}) },   foreign_key: 'highscoreable_id'
  belongs_to :episode, -> { where(scores: {highscoreable_type: 'Episode'}) }, foreign_key: 'highscoreable_id'
  belongs_to :story,   -> { where(scores: {highscoreable_type: 'Story'}) },   foreign_key: 'highscoreable_id'
#  default_scope -> { select("scores.*, score * 1.000 as score")} # Ensure 3 correct decimal places
  enum tab:  [ :SI, :S, :SU, :SL, :SS, :SS2 ]

  # Alternative method to perform rankings which outperforms the Player approach
  # since we leave all the heavy lifting to the SQL interface instead of Ruby.
  def self.rank(ranking, type, tabs, ties = false, n = 0, full = false, players = [])
    return rank_exclude(ranking, type, tabs, ties, n, full, players) if !players.empty? && [:rank, :tied_rank, :points, :avg_points, :avg_rank, :avg_lead].include?(ranking)
    if [:avg_lead, :maxed, :maxable].include?(ranking)
      type = ensure_type(type)
    else
      type = type.nil? ? DEFAULT_TYPES : (!type.is_a?(Array) ? [type] : type)
    end
    scores = self.where(highscoreable_type: type)
    scores = scores.where(tab: tabs) if !tabs.empty?
    scores = scores.where.not(player: players) if !players.empty?
    bench(:start) if BENCHMARK

    case ranking
    when :rank
      scores = scores.where("#{ties ? "tied_rank" : "rank"} <= #{n}")
                     .group(:player_id)
                     .order('count_id desc')
                     .count(:id)
    when :tied_rank
      scores_w  = scores.where("tied_rank <= #{n}")
                        .group(:player_id)
                        .order('count_id desc')
                        .count(:id)
      scores_wo = scores.where("rank <= #{n}")
                        .group(:player_id)
                        .order('count_id desc')
                        .count(:id)
      scores = scores_w.map{ |id, count| [id, count - scores_wo[id].to_i] }
                       .sort_by{ |id, c| -c }
    when :singular
      types = type.map{ |t|
        ids = scores.where(rank: 1, tied_rank: n, highscoreable_type: t)
                    .pluck(:highscoreable_id)
        scores.where(rank: 0, highscoreable_type: t, highscoreable_id: ids)
              .group(:player_id)
              .count(:id)
      }
      scores = types.map(&:keys).flatten.uniq.map{ |id|
        [id, types.map{ |t| t[id].to_i }.sum]
      }.sort_by{ |id, c| -c }
    when :points
      scores = scores.group(:player_id)
                     .order("sum(#{ties ? "20 - tied_rank" : "20 - rank"}) desc")
                     .sum(ties ? "20 - tied_rank" : "20 - rank")
    when :avg_points
      scores = scores.select("count(player_id)")
                     .group(:player_id)
                     .having("count(player_id) >= #{min_scores(type, tabs)}")
                     .order("avg(#{ties ? "20 - tied_rank" : "20 - rank"}) desc")
                     .average(ties ? "20 - tied_rank" : "20 - rank")
    when :avg_rank
      scores = scores.select("count(player_id)")
                     .group(:player_id)
                     .having("count(player_id) >= #{min_scores(type, tabs)}")
                     .order("avg(#{ties ? "tied_rank" : "rank"})")
                     .average(ties ? "tied_rank" : "rank")
    when :avg_lead
      scores = scores.where(rank: [0, 1])
                     .pluck(:player_id, :highscoreable_id, :score)
                     .group_by{ |s| s[1] }
                     .map{ |h, s| [s[0][0], s[0][2] - s[1][2]] }
                     .group_by{ |s| s[0] }
                     .map{ |p, s| [p, s.map(&:last).sum / s.map(&:last).count] }
                     .sort_by{ |p, s| -s }
    when :score
      scores = scores.group(:player_id)
                     .order("sum(score) desc")
                     .sum(:score)
                     .map{ |id, c| [id, round_score(c)] }
    when :maxed
      scores = scores.where(highscoreable_id: HighScore.ties(type, tabs, nil, true, true))
                     .where("tied_rank = 0")   
                     .group(:player_id)
                     .order("count(id) desc")
                     .count(:id)
    when :maxable
      scores = scores.where(highscoreable_id: HighScore.ties(type, tabs, nil, false, true))
                     .where("tied_rank = 0")   
                     .group(:player_id)
                     .order("count(id) desc")
                     .count(:id)
    when :cool
      scores = scores.where("#{ties ? "tied_rank" : "rank"} <= #{n}")
                     .where(cool: true)
                     .group(:player_id)
                     .order("count(id) desc")
                     .count(:id)
    when :star
      scores = scores.where("#{ties ? "tied_rank" : "rank"} <= #{n}")
                     .where(star: true)
                     .group(:player_id)
                     .order("count(id) desc")
                     .count(:id)
    end

    scores = scores.take(NUM_ENTRIES) if !full
    # find all players in advance (better performant)
    players = Player.where(id: scores.map(&:first))
                    .map{ |p| [p.id, p] }
                    .to_h
    ret = scores.map{ |p, c| [players[p], c] }
    ret.reject!{ |p, c| c <= 0  } unless [:avg_rank, :avg_lead].include?(ranking)

    bench(:step) if BENCHMARK
    ret
  end

  # Rankings excluding specified players. Less optimized than the function above
  # because I couldn't find a way to ignore them other than loop through all levels
  # on a one by one basis.
  def self.rank_exclude(ranking, type, tabs, ties = false, n = 0, full = false, players = [])
    bench(:start) if BENCHMARK
    pids = players.map(&:id)
    p = Player.pluck(:id).map{ |id| [id, 0] }.to_h
    q = Player.pluck(:id).map{ |id| [id, 0] }.to_h
    type = [Level, Episode] if type.nil?
    t_rank = 0
    t_score = -1

    [type].flatten.each{ |t|
      (tabs.empty? ? t.all : t.where(tab: tabs)).each{ |e|
        t_rank = 0
        t_score = 3000.0
        if ranking == :avg_lead
          a_id = -1
          a_score = -1
        end
        e.scores.reject{ |s| pids.include?(s.player_id) }.sort_by{ |s| s.rank }.each_with_index{ |s, i|
          if s.score < t_score
            t_rank = i
            t_score = s.score
          end
          case ranking
          when :rank
            (ties ? t_rank : i) <= n ? p[s.player_id] += 1 : break
          when :tied_rank
            t_rank <= n ? (i <= n ? next : p[s.player_id] += 1) : break
          when :points
            p[s.player_id] += 20 - (ties ? t_rank : i)
          when :avg_points
            p[s.player_id] += 20 - (ties ? t_rank : i)
            q[s.player_id] += 1
          when :avg_rank
            p[s.player_id] += ties ? t_rank : i
            q[s.player_id] += 1
          when :avg_lead
            if i == 0
              a_id = s.player_id
              a_score = s.score
            elsif i == 1
              p[a_id] += a_score - s.score
              q[a_id] += 1
            else
              break
            end
          end
        }
      }
    }

    bench(:step) if BENCHMARK
    p = p.select{ |id, c| q[id] > (ranking == :avg_lead ? 0 : min_scores(type, tabs)) }
         .map{ |id, c| [id, c.to_f / q[id]] }
         .to_h if [:avg_points, :avg_rank, :avg_lead].include?(ranking)
    p.sort_by{ |id, c| ranking == :avg_rank ? c : -c }
     .take(NUM_ENTRIES)
     .reject{ |id, c| c == 0 unless [:avg_rank, :avg_lead].include?(ranking) }
     .map{ |id, c| [Player.find(id), c] }
  end

  def self.total_scores(type, tabs, secrets)
    bench(:start) if BENCHMARK
    tabs = (tabs.empty? ? [:SI, :S, :SL, :SU, :SS, :SS2] : tabs)
    tabs = (secrets ? tabs : tabs - [:SS, :SS2])
    ret = self.where(highscoreable_type: type.to_s, tab: tabs, rank: 0)
              .pluck('SUM(score)', 'COUNT(score)')
              .map{ |score, count| [round_score(score.to_f), count.to_i] }
    bench(:step) if BENCHMARK
    ret.first
  end

  def spread
    highscoreable.scores.find_by(rank: 0).score - score
  end

  def demo
    Demo.find_by(replay_id: replay_id, htype: Demo.htypes[highscoreable.class.to_s.downcase.to_sym])
  end

  def format(name_padding = DEFAULT_PADDING, score_padding = 0, show_cools = true)
    "#{star ? "*" : ' '}#{HighScore.format_rank(rank)}: #{player.format_name(name_padding)} - #{"%#{score_padding}.3f" % [score]}#{show_cools && cool ? " 😎" : ""}"
  end
end

# Note: Players used to be referenced by Users, not anymore. Everything has been
# structured to better deal with multiple players and/or users with the same name.
class Player < ActiveRecord::Base
  has_many :scores
  has_many :rank_histories
  has_many :points_histories
  has_many :total_score_histories
  has_many :player_aliases

  # Deprecated since it's slower, see Score::rank
  def self.rankings(&block)
    players = Player.all

    players.map { |p| [p, yield(p)] }
      .sort_by { |a| -a[1] }
  end

  def self.histories(type, attrs, column)
    attrs[:highscoreable_type] ||= ['Level', 'Episode'] # Don't include stories
    hist = type.where(attrs).includes(:player)

    ret = Hash.new { |h, k| h[k] = Hash.new { |h, k| h[k] = 0 } }

    hist.each do |h|
      ret[h.player.name][h.timestamp] += h.send(column)
    end

    ret
  end

  def self.rank_histories(rank, type, tabs, ties)
    attrs = {rank: rank, ties: ties}
    attrs[:highscoreable_type] = type.to_s if type
    attrs[:tab] = tabs if !tabs.empty?

    self.histories(RankHistory, attrs, :count)
  end

  def self.score_histories(type, tabs)
    attrs = {}
    attrs[:highscoreable_type] = type.to_s if type
    attrs[:tab] = tabs if !tabs.empty?

    self.histories(TotalScoreHistory, attrs, :score)
  end

  def self.points_histories(type, tabs)
    attrs = {}
    attrs[:highscoreable_type] = type.to_s if type
    attrs[:tab] = tabs if !tabs.empty?

    self.histories(PointsHistory, attrs, :points)
  end

  # Only works for 1 type at a time
  def self.comparison_(type, tabs, p1, p2)
    type = ensure_type(type)
    request = Score.where(highscoreable_type: type)
    request = request.where(tab: tabs) if !tabs.empty?
    t = type.to_s.downcase.pluralize
    bench(:start) if BENCHMARK
    ids = request.where(player: [p1, p2])
                 .joins("INNER JOIN #{t} ON #{t}.id = scores.highscoreable_id")
                 .group(:highscoreable_id)
                 .having('count(highscoreable_id) > 1')
                 .pluck('MIN(highscoreable_id)')
    scores1 = request.where(highscoreable_id: ids, player: p1)
                     .joins("INNER JOIN #{t} ON #{t}.id = scores.highscoreable_id")
                     .order(:highscoreable_id)
                     .pluck(:rank, :highscoreable_id, "#{t}.name", :score)
    scores2 = request.where(highscoreable_id: ids, player: p2)
                     .joins("INNER JOIN #{t} ON #{t}.id = scores.highscoreable_id")
                     .order(:highscoreable_id)
                     .pluck(:rank, :highscoreable_id, "#{t}.name", :score)
    scores = scores1.zip(scores2).group_by{ |s1, s2| s1[3] <=> s2[3] }
    s1 = request.where(player: p1)
                .where.not(highscoreable_id: ids)
                .joins("INNER JOIN #{t} ON #{t}.id = scores.highscoreable_id")
                .pluck(:rank, :highscoreable_id, "#{t}.name", :score)
                .group_by{ |s| s[0] }
                .map{ |r, s| [r, s.sort_by{ |s| s[1] }] }
                .to_h
    s2 = scores.key?(1)  ? scores[1].group_by{ |s1, s2| s1[0] }
                                   .map{ |r, s| [r, s.sort_by{ |s1, s2| s1[1] }] }
                                   .to_h
                         : {}
    s3 = scores.key?(0)  ? scores[0].group_by{ |s1, s2| s1[0] }
                                   .map{ |r, s| [r, s.sort_by{ |s1, s2| s1[1] }] }
                                   .to_h
                         : {}
    s4 = scores.key?(-1) ? scores[-1].group_by{ |s1, s2| s1[0] }
                                     .map{ |r, s| [r, s.sort_by{ |s1, s2| s2[1] }] }
                                     .to_h
                         : {}
    s5 = request.where(player: p2)
                .where.not(highscoreable_id: ids)
                .joins("INNER JOIN #{t} ON #{t}.id = scores.highscoreable_id")
                .pluck(:rank, :highscoreable_id, "#{t}.name", :score)
                .group_by{ |s| s[0] }
                .map{ |r, s| [r, s.sort_by{ |s| s[1] }] }
                .to_h
    bench(:step) if BENCHMARK
    [s1, s2, s3, s4, s5]
  end

  # Merges the results for each type using the previous method
  def self.comparison(type, tabs, p1, p2)
    type = [Level, Episode] if type.nil?
    ret = (0..4).map{ |t| (0..19).to_a.map{ |r| [r, []] }.to_h }
    [type].flatten.each{ |t|
      scores = comparison_(t, tabs, p1, p2)
      (0..4).each{ |i|
        (0..19).each{ |r|
          ret[i][r] += scores[i][r] if !scores[i][r].nil?
        }
      }
    }
    (0..4).each{ |i|
      (0..19).each{ |r|
        ret[i].delete(r) if ret[i][r].empty?
      }
    }
    ret
  end

  def add_alias(a)
    PlayerAlias.find_or_create_by(player: self, alias: a)
  end

  def print_name
    user = User.where(playername: name).where.not(displayname: nil)
    (user.empty? ? name : user.first.displayname).remove("`")
  end

  def format_name(padding = DEFAULT_PADDING)
    format_string(print_name, padding)
  end

  def truncate_name(length = MAX_PADDING)
    TRUNCATE_NAME ? print_name[0..length] : print_name
  end

  def sanitize_name
    sanitize_filename(print_name)
  end

  def scores_by_type_and_tabs(type, tabs, include = nil)
    ret = scores.where(highscoreable_type: type.nil? ? DEFAULT_TYPES : type.to_s)
    ret = ret.where(tab: tabs) if !tabs.empty?
    case include
    when :scores
      ret.includes(highscoreable: [:scores])
    when :name
      ret.includes(:highscoreable)
    else
      ret
    end
  end

  def top_ns(n, type, tabs, ties)
    scores_by_type_and_tabs(type, tabs).where("#{ties ? "tied_rank" : "rank"} < #{n}")
  end

  # If we're asking for missing 'cool' or 'star' scores, we actually take the
  # scores the player HAS which are missing the cool/star badge.
  # Otherwise, missing includes all the scores the player DOESN'T have.
  def range_ns(a, b, type, tabs, ties, tied = false, cool = false, star = false, missing = false)
    return missing(type, tabs, a, b, ties, tied) if missing && !cool && !star
    if tied
      q = "tied_rank >= #{a} AND tied_rank < #{b} AND NOT (rank >= #{a} AND rank < #{b})"
    else
      rank_type = ties ? "tied_rank" : "rank"
      q = "#{rank_type} >= #{a} AND #{rank_type} < #{b}"
    end
    ret = scores_by_type_and_tabs(type, tabs).where(q)
    ret = ret.where("#{missing ? 'NOT ' : ''}(cool = 1 AND star = 1)") if cool && star
    ret = ret.where(cool: !missing) if cool && !star
    ret = ret.where(star: !missing) if star && !cool
    ret
  end

  def cools(type, tabs, r1 = 0, r2 = 20, ties = false, missing = false)
    range_ns(r1, r2, type, tabs, ties).where(cool: !missing)
  end

  def stars(type, tabs, r1 = 0, r2 = 20, ties = false, missing = false)
    range_ns(r1, r2, type, tabs, ties).where(star: !missing)
  end

  def scores_by_rank(type, tabs, r1 = 0, r2 = 20)
    bench(:start) if BENCHMARK
    ret = scores_by_type_and_tabs(type, tabs, :name).where("rank >= #{r1} AND rank < #{r2}")
                                                    .order('rank, highscoreable_type DESC, highscoreable_id')
    bench(:step) if BENCHMARK
    ret
  end

  def score_counts(tabs, ties)
    bench(:start) if BENCHMARK
    counts = {
      levels:   scores_by_type_and_tabs(Level,   tabs).group(ties ? :tied_rank : :rank).order(ties ? :tied_rank : :rank).count(:id),
      episodes: scores_by_type_and_tabs(Episode, tabs).group(ties ? :tied_rank : :rank).order(ties ? :tied_rank : :rank).count(:id),
      stories:  scores_by_type_and_tabs(Story,   tabs).group(ties ? :tied_rank : :rank).order(ties ? :tied_rank : :rank).count(:id)
    }
    bench(:step) if BENCHMARK
    counts
  end

  def missing(type, tabs, a, b, ties, tied = false)
    type = DEFAULT_TYPES.map(&:constantize) if type.nil?
    bench(:start) if BENCHMARK
    scores = [type].flatten.map{ |t|
      ids = range_ns(a, b, t, tabs, ties, tied, false, false, false).pluck(:highscoreable_id)
      (tabs.empty? ? t : t.where(tab: tabs)).where.not(id: ids).order(:id).pluck(:name)
    }.flatten
    bench(:step) if BENCHMARK
    scores
  end

  def improvable_scores(type, tabs, a = 0, b = 20, ties = false, cool = false, star = false)
    type = ensure_type(type) # only works for a single type
    bench(:start) if BENCHMARK
    ttype = ties ? 'tied_rank' : 'rank'
    ids = scores_by_type_and_tabs(type, tabs).where("#{ttype} >= #{a} AND #{ttype} < #{b}")
    ids = ids.where(cool: true) if cool
    ids = ids.where(star: true) if star
    ids = ids.pluck(:highscoreable_id, :score).to_h
    ret = Score.where(highscoreable_type: type.to_s, highscoreable_id: ids.keys, rank: 0)
    ret = ret.pluck(:highscoreable_id, :score)
             .map{ |id, s| [id, s - ids[id]] }
             .sort_by{ |s| -s[1] }
             .take(NUM_ENTRIES)
             .map{ |id, s| [type.find(id).name, s] }
    bench(:step) if BENCHMARK
    ret
  end

  def points(type, tabs)
    bench(:start) if BENCHMARK
    points = scores_by_type_and_tabs(type, tabs).sum('20 - rank')
    bench(:step) if BENCHMARK
    points
  end

  def average_points(type, tabs)
    bench(:start) if BENCHMARK
    scores = scores_by_type_and_tabs(type, tabs).average('20 - rank')
    bench(:step) if BENCHMARK
    scores
  end

  def total_score(type, tabs)
    bench(:start) if BENCHMARK
    scores = scores_by_type_and_tabs(type, tabs).sum(:score)
    bench(:step) if BENCHMARK
    scores
  end

  def singular_(type, tabs, plural = false)
    req = Score.where(highscoreable_type: type.to_s)
    req = req.where(tab: tabs) if !tabs.empty?
    ids = req.where("rank = 1 AND tied_rank = #{plural ? 0 : 1}").pluck(:highscoreable_id)
    scores_by_type_and_tabs(type, tabs, :name).where(rank: 0, highscoreable_id: ids)
  end

  def singular(type, tabs, plural = false)
    bench(:start) if BENCHMARK
    type = type.nil? ? DEFAULT_TYPES : [type.to_s]
    ret = type.map{ |t| singular_(t, tabs, plural) }.flatten#.group_by(&:rank)
    bench(:step) if BENCHMARK
    ret
  end

  def average_lead(type, tabs)
    type = ensure_type(type) # only works for a single type
    bench(:start) if BENCHMARK

    ids = top_ns(1, type, tabs, false).pluck('highscoreable_id')
    ret = Score.where(highscoreable_type: type.to_s, highscoreable_id: ids, rank: [0, 1])
    ret = ret.where(tab: tabs) if !tabs.empty?
    ret = ret.pluck(:highscoreable_id, :score)
    count = ret.count / 2
    return 0 if count == 0
    ret = ret.group_by(&:first).map{ |id, sc| (sc[0][1] - sc[1][1]).abs }.sum / count
## alternative method, faster when the player has many 0ths but slower otherwise (usual outcome)
#    ret = Score.where(highscoreable_type: type.to_s, rank: [0, 1])
#    ret = ret.where(tab: tabs) if !tabs.empty?
#    ret = ret.pluck(:player_id, :highscoreable_id, :score)
#             .group_by{ |s| s[1] }
#             .map{ |h, s| s[0][2] - s[1][2] if s[0][0] == id }
#             .compact
#    count = ret.count
#    return 0 if count == 0
#    ret = ret.sum / count

    bench(:step) if BENCHMARK
    ret
  end

  def table(rank, ties, a, b, cool = false, star = false)
    ttype = ties ? 'tied_rank' : 'rank'
    [Level, Episode, Story].map do |type|
      if ![:maxed, :maxable].include?(rank)
        queryBasic = scores.where(highscoreable_type: type)
                          .where(!cool.blank? ? 'cool = 1' : '')
                          .where(!star.blank? ? 'star = 1' : '')
        query = queryBasic.where(!a.blank? ? "#{ttype} >= #{a}" : '')
                          .where(!b.blank? ? "#{ttype} < #{b}" : '')
                          .group(:tab)
      end
      case rank
      when :rank
        query.count(:id).to_h
      when :tied_rank
        scores1 = queryBasic.where("tied_rank >= #{a} AND tied_rank < #{b}")
                            .group(:tab)
                            .count(:id)
                            .to_h
        scores2 = queryBasic.where("rank >= #{a} AND rank < #{b}")
                            .group(:tab)
                            .count(:id)
                            .to_h
        scores1.map{ |tab, count| [tab, count - scores2[tab]] }.to_h
      when :points
        query.sum("20 - #{ttype}").to_h
      when :score
        query.sum(:score).to_h
      when :avg_points
        query.average("20 - #{ttype}").to_h
      when :avg_rank
        query.average(ttype).to_h
      when :maxed
        HighScore.ties(type, [], nil, true, false)
                 .select{ |t| t[1] == t[2] }
                 .group_by{ |t| t[0].split("-")[0] }
                 .map{ |tab, scores| [formalize_tab(tab), scores.size] }
                 .to_h
      when :maxable
        HighScore.ties(type, [], nil, false, false)
                 .select{ |t| t[1] < t[2] }  
                 .group_by{ |t| t[0].split("-")[0] }
                 .map{ |tab, scores| [formalize_tab(tab), scores.size] }
                 .to_h
      else
        query.count(:id).to_h
      end
    end
  end
end

class LevelAlias < ActiveRecord::Base
  belongs_to :level
end

class PlayerAlias < ActiveRecord::Base
  belongs_to :player
end

class Role < ActiveRecord::Base
  def self.exists(discord_id, role)
    !self.find_by(discord_id: discord_id, role: role).nil?
  end

  def self.add(user, role)
    self.find_or_create_by(discord_id: user.id, role: role)
    User.find_or_create_by(username: user.username).update(discord_id: user.id)
  end

  def self.owners(role)
    User.where(discord_id: self.where(role: role).pluck(:discord_id))
  end
end

class User < ActiveRecord::Base
  def player
    Player.find_by(name: playername)
  end

  def player=(person)
    name = person.class == Player ? person.name : person.to_s
    self.playername = name
    self.save
  end

  def self.search(name, tag = nil)
    $bot.servers[SERVER_ID].users.select{ |u| u.username == name && (!tag.nil? ? u.tag == tag : true) }
  end
end

class GlobalProperty < ActiveRecord::Base
end

class RankHistory < ActiveRecord::Base
  belongs_to :player
  enum tab: [:SI, :S, :SU, :SL, :SS, :SS2]

  def self.compose(rankings, type, tab, rank, ties, time)
    rankings.select { |r| r[1] > 0 }.map do |r|
      {
        highscoreable_type: type.to_s,
        rank:               rank,
        ties:               ties,
        tab:                tab,
        player:             r[0],
        count:              r[1],
        metanet_id:         r[0].metanet_id,
        timestamp:          time
      }
    end
  end
end

class PointsHistory < ActiveRecord::Base
  belongs_to :player
  enum tab: [:SI, :S, :SU, :SL, :SS, :SS2]

  def self.compose(rankings, type, tab, time)
    rankings.select { |r| r[1] > 0 }.map do |r|
      {
        timestamp:          time,
        tab:                tab,
        highscoreable_type: type.to_s,
        player:             r[0],
        metanet_id:         r[0].metanet_id,
        points:             r[1]
      }
    end
  end
end

class TotalScoreHistory < ActiveRecord::Base
  belongs_to :player
  enum tab: [:SI, :S, :SU, :SL, :SS, :SS2]

  def self.compose(rankings, type, tab, time)
    rankings.select { |r| r[1] > 0 }.map do |r|
      {
        timestamp:          time,
        tab:                tab,
        highscoreable_type: type.to_s,
        player:             r[0],
        metanet_id:         r[0].metanet_id,
        score:              r[1]
      }
    end
  end
end

class Video < ActiveRecord::Base
  belongs_to :highscoreable, polymorphic: true

  def format_challenge
    return (challenge == "G++" || challenge == "?!") ? challenge : "#{challenge} (#{challenge_code})"
  end

  def format_author
    return "#{author} (#{author_tag})"
  end

  def format_description
    "#{format_challenge} by #{format_author}"
  end
end

class Challenge < ActiveRecord::Base
  belongs_to :level

  def objs
    {
      "G" => self.g,
      "T" => self.t,
      "O" => self.o,
      "C" => self.c,
      "E" => self.e
    }
  end

  def type
    index == 0 ? '!' : '?'
  end

  def count
    objs.select{ |k, v| v != 0 }.count
  end

  def format_type
    "[" + type * count + "]"
  end

  def format_objs
    objs.map{ |k, v|
      v == 1 ? "#{k}++" : (v == -1 ? "#{k}--" : "")
    }.join
  end

  def format(pad)
    format_type + " " * [1, pad - count + 1].max + format_objs
  end
end

class Archive < ActiveRecord::Base
  belongs_to :player
  belongs_to :highscoreable, polymorphic: true
  enum tab: [:SI, :S, :SU, :SL, :SS, :SS2]

  # Returns the leaderboards at a particular point in time
  def self.scores(highscoreable, date)
    self.select('metanet_id', 'max(score)')
        .where(highscoreable: highscoreable)
        .where("unix_timestamp(date) <= #{date}")
        .group('metanet_id')
        .order('max(score) desc, max(replay_id) asc')
        .take(20)
        .map{ |s|
          [s.metanet_id.to_i, s['max(score)'].to_i]
        }
  end

  # Return a list of all dates where a highscoreable changed
  # We consider dates less than MAX_SECS apart to be the same
  def self.changes(highscoreable)
    dates = self.where(highscoreable: highscoreable)
                .select('unix_timestamp(date)')
                .distinct
                .pluck('unix_timestamp(date)')
                .sort
    dates[0..-2].each_with_index.select{ |d, i| dates[i + 1] - d > MAX_SECS }.map(&:first).push(dates.last)
  end

  # Return a list of all 0th holders in history on a specific highscoreable
  # until a certain date (nil = present)
  # Care must be taken when the 0th was improved multiple times in the same update
  def self.zeroths(highscoreable, date = nil)
    dates = changes(highscoreable)
    return [] if dates.size == 0
    prev_date = dates[0]
    zeroth = scores(highscoreable, prev_date).first
    zeroths = [zeroth]
    date = Time.now.to_i if date.nil?

    dates[0..-2].each_with_index.reject{ |d, i| dates[i + 1] > date }.each{ |d, i|
      a = self.where(highscoreable: highscoreable)
              .where("unix_timestamp(date) > #{d} AND unix_timestamp(date) <= #{dates[i + 1]}")
              .order('score DESC')
              .first
      if a.score > zeroth[1]
        zeroth = [a.metanet_id, a.score]
        zeroths.push(zeroth)
      end
    }
    zeroths.map(&:first)
  end
  
  def self.format_scores(board, zeroths = [])
    pad = board.map{ |s| ("%.3f" % (s[1].to_f / 60.0)).length.to_i }.max
    board.each_with_index.map{ |s, i|
      star = zeroths.include?(s[0]) ? '*' : ' '
      "#{star}#{"%02d" % i}: #{format_string(Player.find_by(metanet_id: s[0]).print_name)} - #{"%#{pad}.3f" % (s[1].to_f / 60.0)}"
    }.join("\n")
  end

  # Clean archive of cheated scores
  def self.sanitize
    # Store results to print summary after sanitization
    ret = {}

    # Delete archives by ignored players
    query = Archive.where(metanet_id: IGNORED_IDS)
    ret['archive_del'] = query.count.to_i
    query.each(&:wipe)

    # Delete individual archives
    ret['archive_ind_del'] = 0
    ["Level", "Episode", "Story"].each{ |mode|
      query = Archive.where(highscoreable_type: mode, replay_id: PATCH_IND_DEL[mode.downcase.to_sym])
      ret['archive_ind_del'] += query.count.to_i
      query.each(&:wipe)
    }

    # Delete demos with missing archives
    query = Demo.where.not(replay_id: Archive.all.pluck(:replay_id))
    ret['orphan_demos'] = query.count.to_i
    query.each(&:destroy)

    # Patch archives
    # ONLY EXECUTE THIS ONCE!! Otherwise, the scores will be altered multiple times
    #s = Archive.find_by(highscoreable_type: "Level", replay_id: 3758900)
    #s.score -= 6 * 60;
    #s.save
    #s = Archive.find_by(highscoreable_type: "Episode", replay_id: 5067031)
    #s.score -= 6 * 60;
    #s.save
    #PATCH_RUNS.each{ |mode, entries|
    #  entries.each{ |id, entry|
    #    Archive.where(highscoreable_type: mode.to_s.capitalize, highscoreable_id: id).where("replay_id <= ?", entry[0]).each{ |a|
    #      a.score += entry[1] * 60
    #      a.save
    #    }
    #  }
    #}

    ret
  end

  # Returns the rank of the player at a particular point in time
  def find_rank(time)
    old_score = Archive.scores(self.highscoreable, time)
                       .each_with_index
                       .map{ |s, i| [i, s[0], s[1]] }
                       .select{ |s| s[1] == self.metanet_id }
    old_score.empty? ? 20 : old_score.first[0]
  end

  def format_score
    "%.3f" % self.score.to_f / 60.0
  end

  def demo
    Demo.find(self.id).demo
  end

  # Remove both the archive and its demo from the DB
  def wipe
    Demo.find(self.id).destroy
    self.destroy
  end
end

class Demo < ActiveRecord::Base
  #----------------------------------------------------------------------------#
  #                    METANET REPLAY FORMAT DOCUMENTATION                     |
  #----------------------------------------------------------------------------#
  # REPLAY DATA:                                                               |
  #    4B  - Query type                                                        |
  #    4B  - Replay ID                                                         |
  #    4B  - Level ID                                                          |
  #    4B  - User ID                                                           |
  #   Rest - Demo data compressed with zlib                                    |
  #----------------------------------------------------------------------------#
  # LEVEL DEMO DATA FORMAT:                                                    |
  #     1B - Unknown                                                           |
  #     4B - Data length                                                       |
  #     4B - Unknown                                                           |
  #     4B - Frame count                                                       |
  #     4B - Level ID                                                          |
  #    13B - Unknown                                                           |
  #   Rest - Demo                                                              |
  #----------------------------------------------------------------------------#
  # EPISODE DEMO DATA FORMAT:                                                  |
  #     4B - Unknown                                                           |
  #    20B - Block length for each level demo (5 * 4B)                         |
  #   Rest - Demo data (5 consecutive blocks, see above)                       |
  #----------------------------------------------------------------------------#
  # STORY DEMO DATA FORMAT:                                                    |
  #     4B - Unknown                                                           |
  #     4B - Demo data block size                                              |
  #   100B - Block length for each level demo (25 * 4B)                        |
  #   Rest - Demo data (25 consecutive blocks, see above)                      |
  #----------------------------------------------------------------------------#
  # DEMO FORMAT:                                                               |
  #   * One byte per frame.                                                    |
  #   * First bit for jump, second for right and third for left.               |
  #   * Suicide is 12 (0C).                                                    |
  #   * The first frame is fictional and must be ignored.                      |
  #----------------------------------------------------------------------------#
  enum htype: [:level, :episode, :story]

  def score
    Archive.find(self.id)
  end

  def qt
    case htype.to_sym
    when :level
      0
    when :episode
      1
    when :story
      4
    else
      -1 # error checking
    end
  end

  def demo_uri(steam_id)
    URI.parse("https://dojo.nplusplus.ninja/prod/steam/get_replay?steam_id=#{steam_id}&steam_auth=&replay_id=#{replay_id}&qt=#{qt}")
  end

  def get_demo
    attempts ||= 0
    initial_id = get_last_steam_id
    response = Net::HTTP.get_response(demo_uri(initial_id))
    while response.body == INVALID_RESP
      deactivate_last_steam_id
      update_last_steam_id
      break if get_last_steam_id == initial_id
      response = Net::HTTP.get_response(demo_uri(get_last_steam_id))
    end
    return 1 if response.code.to_i == 200 && response.body.empty? # replay does not exist
    return nil if response.body == INVALID_RESP
    raise "502 Bad Gateway" if response.code.to_i == 502
    activate_last_steam_id
    response.body
  rescue => e
    if (attempts += 1) < RETRIES
      if SHOW_ERRORS
        err("error getting demo with id #{replay_id}: #{e}")
      end
      retry
    else
      return nil
    end
  end

  def parse_demo(replay)
    data   = Zlib::Inflate.inflate(replay[16..-1])
    header = {level: 0, episode:  4, story:   8}[htype.to_sym]
    offset = {level: 0, episode: 24, story: 108}[htype.to_sym]
    count  = {level: 1, episode:  5, story:  25}[htype.to_sym]

    framecounts = []
    lengths = (0..count - 1).map{ |d| _unpack(data[header + 4 * d..header + 4 * (d + 1) - 1]) }
    lengths = [_unpack(data[1..4])] if htype.to_sym == :level
    demos = (0..count - 1).map{ |d|
      offset += lengths[d - 1] unless d == 0
      raw_replay = data[offset..offset + lengths[d] - 1]
      framecounts << _unpack(raw_replay[9..12])
      raw_replay[30..-1]
    }
    # Add framecount and goldcount to corresponding archive
    # before Zlibbing later
    if !score.nil?
      framecount = framecounts.sum
      score.update(
        framecount: framecount,
        gold: framecount != -1 ? (((score.score + framecount).to_f / 60 - 90) / 2).round : -1
      )
    end
    demos
  end

  def encode_demo(replay)
    replay = [replay] if replay.class == String
    Zlib::Deflate.deflate(replay.join('&'), 9)
  end

  def decode_demo
    return nil if demo.nil?
    demos = Zlib::Inflate.inflate(demo).split('&')
    return (demos.size == 1 ? demos.first.scan(/./m).map(&:ord) : demos.map{ |d| d.scan(/./m).map(&:ord) })
  end

  # Do not delete, it's not redundant, the field in Archive uses this for its
  # first computation
  def framecount
    return -1 if demo.nil?
    demos = decode_demo
    return (htype.to_sym == :level ? demos.size : demos.map(&:size).sum)
  end

  def update_demo
    replay = get_demo
    return nil if replay.nil? # replay was not fetched successfully
    if replay == 1 # replay does not exist
      ActiveRecord::Base.transaction do
        self.update(expired: true)
      end
      return nil
    end
    ActiveRecord::Base.transaction do
      self.update(
        demo: encode_demo(parse_demo(replay)),
        expired: false
      )
    end
  rescue => e
    if SHOW_ERRORS
      err("error parsing demo with id #{replay_id}: #{e}")
    end
    return nil
  end
end

module Twitch extend self

  GAME_IDS = {
#    'N'     => 12273, # Commented because it's usually non-N related :(
    'N+'    => 18983,
    'Nv2'   => 105456,
    'N++'   => 369385
#    'GTASA' => 6521 # This is for testing purposes, since often there are no N streams live
  }

  def get_twitch_token
    GlobalProperty.find_by(key: 'twitch_token').value
  end

  def set_twitch_token(token)
    GlobalProperty.find_by(key: 'twitch_token').update(value: token)
  end

  def table_header
    "#{"Player".ljust(15, " ")} #{"Title".ljust(35, " ")} #{"Time".ljust(12, " ")} #{"Views".ljust(4, " ")}\n#{"-" * 70}"
  end

  def format_stream(s)
    name  = to_ascii(s['user_name'].remove("\n").strip[0..14]).ljust(15, ' ')
    title = to_ascii(s['title'].remove("\n").strip[0..34]).ljust(35, ' ')
    time  = "#{(Time.now - DateTime.parse(s['started_at']).to_time).to_i / 60} mins ago".rjust(12, ' ')
    views = s['viewer_count'].to_s.rjust(5, ' ')
    "#{name} #{title} #{time} #{views}"
  end

  def update_twitch_token
    res = Net::HTTP.post_form(
      URI.parse("https://id.twitch.tv/oauth2/token"),
      {
        client_id: $config['twitch_id'],
        client_secret: ENV['TWITCH_SECRET'],
        grant_type: 'client_credentials'
      }
    )
    if res.code.to_i == 401
      err("TWITCH: Unauthorized to perform requests, please verify you have this correctly configured.")      
    elsif res.code.to_i != 200
      err("TWITCH: App access token request failed.")
    else
      $twitch_token = JSON.parse(res.body)['access_token']
      set_twitch_token($twitch_token)
    end
  rescue
    err("TWITCH: App access token request method failed.")
    sleep(5)
    retry
  end

  # TODO: Add attempts to the loop, raise if fail
  def get_twitch_game_id(name)
    update_twitch_token if $twitch_token.nil?
    uri = URI("https://api.twitch.tv/helix/games?name=#{name}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    loop do
      res = http.get(
        uri.request_uri,
        {
          'Authorization' => "Bearer #{$twitch_token}",
          'Client-Id' => $config['twitch_id']
        }
      )
      if res.code.to_i == 401
        update_twitch_token
        sleep(5)
      elsif res.code.to_i != 200
        err("TWITCH: Game ID request failed.")
        sleep(5)
      else
        return JSON.parse(res.body)['id'].to_i
      end
    end
  rescue
    err("TWITCH: Game ID request method failed.")
    sleep(5)
    retry
  end

 # TODO: Add attempts to the loops, raise if fail
 # TODO: Add offset/pagination for when there are many results
  def get_twitch_streams(name, offset = nil)
    if !GAME_IDS.key?(name)
      err("TWITCH: Supplied game not known.")
      return
    end
    while $twitch_token.nil?
      update_twitch_token
      sleep(5)
    end
    uri = URI("https://api.twitch.tv/helix/streams?first=100&game_id=#{GAME_IDS[name]}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    res = nil
    loop do
      res = http.get(
        uri.request_uri,
        {
          'Authorization' => "Bearer #{$twitch_token}",
          'Client-Id' => $config['twitch_id']
        }
      )
      if res.code.to_i == 401
        update_twitch_token
        sleep(5)
      elsif res.code.to_i != 200
        err("TWITCH: Stream list request for #{name} failed.")
        sleep(5)
      else
        break
      end
    end
    JSON.parse(res.body)['data'].sort_by{ |s| s['user_name'].downcase }
  rescue
    err("TWITCH: Stream list request method for #{name} failed.")
    sleep(5)
    retry
  end

  def update_twitch_streams
    GAME_IDS.each{ |game, id|
      $twitch_streams[game] = get_twitch_streams(game)
    }
  end

end
