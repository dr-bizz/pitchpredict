# PitchPredict seed data — World Cup 2026.
#
# NOTE: these seeds are a DESTRUCTIVE REBUILD (db:seed:replant style): every run
# wipes all rows (including users and their sessions) and recreates the world
# from scratch. Re-running is therefore safe and deterministic, but it logs
# everybody out and regenerates all ids.
#
# NOTE: group draws, knockout pairings and all results are illustrative, not the
# real 2026 draw. Teams are real, plausible qualifiers with correct FIFA codes.
#
# NOTE: the schedule is shifted ~10 days earlier than the real tournament
# (group stage 2026-06-01 → 2026-06-25) so that, as of 2026-06-12, roughly half
# the group stage is already finished and the leaderboard shows real numbers.
#
# Seeding strategy: Prediction and ChampionPick carry kickoff-lock validations,
# so we seed in two phases. Phase 1 creates every fixture with a provisional
# *future* kickoff (past kickoffs temporarily shifted +60 days), then creates
# predictions and champion picks while the tournament is still "open". Phase 2
# backdates the past fixtures to their real kickoff, records final scores,
# marks them finished and runs ScoringService.score_fixture! on each. This way
# every record passes its real validations — nothing is saved with
# `validate: false`.

RNG = Random.new(2026) # deterministic results on every replant
NOW = Time.current

TEAMS_BY_GROUP = {
  "A" => [ [ "Mexico", "MEX", "🇲🇽", "CONCACAF" ], [ "South Korea", "KOR", "🇰🇷", "AFC" ],
          [ "Switzerland", "SUI", "🇨🇭", "UEFA" ], [ "South Africa", "RSA", "🇿🇦", "CAF" ] ],
  "B" => [ [ "Canada", "CAN", "🇨🇦", "CONCACAF" ], [ "Croatia", "CRO", "🇭🇷", "UEFA" ],
          [ "Morocco", "MAR", "🇲🇦", "CAF" ], [ "Jordan", "JOR", "🇯🇴", "AFC" ] ],
  "C" => [ [ "Brazil", "BRA", "🇧🇷", "CONMEBOL" ], [ "Norway", "NOR", "🇳🇴", "UEFA" ],
          [ "Ghana", "GHA", "🇬🇭", "CAF" ], [ "New Zealand", "NZL", "🇳🇿", "OFC" ] ],
  "D" => [ [ "United States", "USA", "🇺🇸", "CONCACAF" ], [ "Japan", "JPN", "🇯🇵", "AFC" ],
          [ "Scotland", "SCO", "🏴󠁧󠁢󠁳󠁣󠁴󠁿", "UEFA" ], [ "Paraguay", "PAR", "🇵🇾", "CONMEBOL" ] ],
  "E" => [ [ "Spain", "ESP", "🇪🇸", "UEFA" ], [ "Ecuador", "ECU", "🇪🇨", "CONMEBOL" ],
          [ "Ivory Coast", "CIV", "🇨🇮", "CAF" ], [ "Uzbekistan", "UZB", "🇺🇿", "AFC" ] ],
  "F" => [ [ "Argentina", "ARG", "🇦🇷", "CONMEBOL" ], [ "Senegal", "SEN", "🇸🇳", "CAF" ],
          [ "Austria", "AUT", "🇦🇹", "UEFA" ], [ "Australia", "AUS", "🇦🇺", "AFC" ] ],
  "G" => [ [ "France", "FRA", "🇫🇷", "UEFA" ], [ "Colombia", "COL", "🇨🇴", "CONMEBOL" ],
          [ "Egypt", "EGY", "🇪🇬", "CAF" ], [ "Saudi Arabia", "KSA", "🇸🇦", "AFC" ] ],
  "H" => [ [ "England", "ENG", "🏴󠁧󠁢󠁥󠁮󠁧󠁿", "UEFA" ], [ "Uruguay", "URU", "🇺🇾", "CONMEBOL" ],
          [ "Tunisia", "TUN", "🇹🇳", "CAF" ], [ "Iran", "IRN", "🇮🇷", "AFC" ] ],
  "I" => [ [ "Germany", "GER", "🇩🇪", "UEFA" ], [ "Algeria", "ALG", "🇩🇿", "CAF" ],
          [ "Curacao", "CUW", "🇨🇼", "CONCACAF" ], [ "Iraq", "IRQ", "🇮🇶", "AFC" ] ],
  "J" => [ [ "Portugal", "POR", "🇵🇹", "UEFA" ], [ "Cape Verde", "CPV", "🇨🇻", "CAF" ],
          [ "Panama", "PAN", "🇵🇦", "CONCACAF" ], [ "Qatar", "QAT", "🇶🇦", "AFC" ] ],
  "K" => [ [ "Netherlands", "NED", "🇳🇱", "UEFA" ], [ "Nigeria", "NGA", "🇳🇬", "CAF" ],
          [ "Costa Rica", "CRC", "🇨🇷", "CONCACAF" ], [ "Bolivia", "BOL", "🇧🇴", "CONMEBOL" ] ],
  "L" => [ [ "Belgium", "BEL", "🇧🇪", "UEFA" ], [ "Italy", "ITA", "🇮🇹", "UEFA" ],
          [ "Honduras", "HON", "🇭🇳", "CONCACAF" ], [ "DR Congo", "COD", "🇨🇩", "CAF" ] ]
}.freeze

# The 16 real World Cup 2026 host stadiums.
STADIUMS = [
  [ "Estadio Azteca", "Mexico City", "Mexico" ],
  [ "Estadio Akron", "Guadalajara", "Mexico" ],
  [ "Estadio BBVA", "Monterrey", "Mexico" ],
  [ "BMO Field", "Toronto", "Canada" ],
  [ "BC Place", "Vancouver", "Canada" ],
  [ "MetLife Stadium", "East Rutherford", "USA" ],
  [ "SoFi Stadium", "Inglewood", "USA" ],
  [ "AT&T Stadium", "Arlington", "USA" ],
  [ "NRG Stadium", "Houston", "USA" ],
  [ "Mercedes-Benz Stadium", "Atlanta", "USA" ],
  [ "Hard Rock Stadium", "Miami Gardens", "USA" ],
  [ "Lincoln Financial Field", "Philadelphia", "USA" ],
  [ "Lumen Field", "Seattle", "USA" ],
  [ "Levi's Stadium", "Santa Clara", "USA" ],
  [ "Gillette Stadium", "Foxborough", "USA" ],
  [ "Arrowhead Stadium", "Kansas City", "USA" ]
].freeze

PLAYER_NAMES = [
  "Maya Okafor", "Liam Castellanos", "Priya Raman", "Jonas Weber",
  "Sofia Marchetti", "Tomás Herrera", "Aisha Diallo", "Kenji Nakamura",
  "Hannah O'Brien", "Mateus Figueiredo", "Ingrid Sørensen", "Omar Haddad"
].freeze

CONTENDER_CODES = %w[BRA FRA ARG ESP ENG GER POR NED ITA USA MEX URU].freeze

# Realistic-ish goal distribution (mean ~1.3 goals a side).
GOAL_WEIGHTS = [ 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 3, 3, 4 ].freeze

def random_goals
  GOAL_WEIGHTS.sample(random: RNG)
end

puts "== Clearing existing data (destructive replant) =="
ActiveRecord::Base.transaction do
  [ Prediction, ChampionPick, Session, Fixture, Team, Stadium, User ].each(&:delete_all)

  puts "== Stadiums =="
  stadiums = STADIUMS.map { |name, city, country| Stadium.create!(name:, city:, country:) }

  puts "== Teams =="
  teams_by_group = TEAMS_BY_GROUP.to_h do |group_name, rows|
    teams = rows.map do |name, code, flag_emoji, confederation|
      Team.create!(name:, code:, flag_emoji:, confederation:, group_name:)
    end
    [ group_name, teams ]
  end

  # ---- Phase 1: fixtures with provisional (always future) kickoffs ----------
  # real_kickoffs remembers the true kickoff for fixtures temporarily shifted
  # into the future so prediction/champion-pick lock validations stay open.
  real_kickoffs = {}

  create_fixture = lambda do |home, away, stadium, kickoff, stage|
    provisional = kickoff > NOW ? kickoff : kickoff + 60.days
    fixture = Fixture.create!(home_team: home, away_team: away, stadium:,
                              kickoff_at: provisional, stage:)
    real_kickoffs[fixture] = kickoff
    fixture
  end

  puts "== Group-stage fixtures (72) =="
  # Each group of 4 plays a round robin: matchdays 1/2/3 start June 1 / 9 / 17,
  # staggered by group so kickoffs spread across 2026-06-01..2026-06-24.
  group_pairings = [ [ 0, 1 ], [ 2, 3 ], [ 0, 2 ], [ 1, 3 ], [ 0, 3 ], [ 1, 2 ] ]
  matchday_start_day = [ 1, 9, 17 ]
  kickoff_hours = [ 16, 19, 22 ] # UTC

  group_fixtures = []
  teams_by_group.each_with_index do |(_group, teams), g_index|
    group_pairings.each_with_index do |(h, a), m_index|
      day = matchday_start_day[m_index / 2] + (g_index % 8)
      kickoff = Time.zone.local(2026, 6, day, kickoff_hours[(g_index + m_index) % 3])
      stadium = stadiums[((g_index * 6) + m_index) % stadiums.length]
      group_fixtures << create_fixture.call(teams[h], teams[a], stadium, kickoff, :group)
    end
  end

  puts "== Knockout placeholder fixtures (32) =="
  # NOTE: illustrative bracket — group winners (12) + runners-up (12) + the 8
  # "best third-placed" teams (groups A–H here), seeded so no round-of-32 tie
  # repeats a group pairing.
  winners = teams_by_group.values.map { |t| t[0] }
  runners = teams_by_group.values.map { |t| t[1] }
  thirds  = teams_by_group.values.first(8).map { |t| t[2] }
  bracket = winners + runners + thirds # 32 teams

  knockout_stadium = ->(i) { stadiums[i % stadiums.length] }

  16.times do |i| # Round of 32: June 28 – July 3
    kickoff = Time.zone.local(2026, 6, 28, kickoff_hours[i % 3]) + (i / 3).days
    create_fixture.call(bracket[i], bracket[31 - i], knockout_stadium.call(i), kickoff, :r32)
  end
  8.times do |j| # Round of 16: July 4 – 7
    kickoff = Time.zone.local(2026, 7, 4, kickoff_hours[j % 3]) + (j / 2).days
    create_fixture.call(bracket[2 * j], bracket[(2 * j) + 1], knockout_stadium.call(j + 3), kickoff, :r16)
  end
  4.times do |k| # Quarter-finals: July 9 – 10
    kickoff = Time.zone.local(2026, 7, 9, kickoff_hours[k % 2]) + (k / 2).days
    create_fixture.call(bracket[4 * k], bracket[(4 * k) + 2], knockout_stadium.call(k + 6), kickoff, :qf)
  end
  2.times do |s| # Semi-finals: July 14 – 15
    kickoff = Time.zone.local(2026, 7, 14, 19) + s.days
    create_fixture.call(bracket[8 * s], bracket[(8 * s) + 4], knockout_stadium.call(s + 10), kickoff, :sf)
  end
  # Third place in Miami, final at MetLife — the real 2026 venues.
  create_fixture.call(bracket[4], bracket[12], stadiums[10], Time.zone.local(2026, 7, 18, 19), :third_place)
  create_fixture.call(bracket[0], bracket[8], stadiums[5], Time.zone.local(2026, 7, 19, 19), :final)

  # ---- Users -----------------------------------------------------------------
  puts "== Users =="
  password = "worldcup2026"
  User.create!(name: "Alex Admin", email_address: "admin@pitchpredict.app",
               password:, password_confirmation: password, role: :admin)
  demo = User.create!(name: "Dani Demo", email_address: "demo@pitchpredict.app",
                      password:, password_confirmation: password, role: :player)
  players = [ demo ] + PLAYER_NAMES.map.with_index do |name, i|
    User.create!(name:, email_address: "player#{i + 1}@pitchpredict.app",
                 password:, password_confirmation: password, role: :player)
  end

  # ---- Predictions + champion picks (while every fixture is still open) -----
  puts "== Predictions and champion picks =="
  contenders = CONTENDER_CODES.map { |code| Team.find_by!(code:) }
  players.each do |player|
    # Each player predicts 60–100% of the group fixtures.
    coverage = RNG.rand(0.60..1.0)
    group_fixtures.sample((group_fixtures.size * coverage).round, random: RNG).each do |fixture|
      player.predictions.create!(fixture:, home_score: random_goals, away_score: random_goals)
    end
    player.create_champion_pick!(team: contenders.sample(random: RNG))
  end

  # ---- Phase 2: backdate past fixtures, record results, score ---------------
  puts "== Results for fixtures already played =="
  # NOTE: the finished cutoff is Time.current rather than literally 2026-06-12
  # 00:00, so a seed run later in the day never leaves a past fixture stuck on
  # "scheduled" with no score.
  finished = 0
  real_kickoffs.each do |fixture, kickoff|
    next unless kickoff <= NOW

    fixture.update!(kickoff_at: kickoff, status: :finished,
                    home_score: random_goals, away_score: random_goals)
    ScoringService.score_fixture!(fixture)
    finished += 1
  end

  puts "Seeded: #{Team.count} teams, #{Stadium.count} stadiums, " \
       "#{Fixture.count} fixtures (#{finished} finished), " \
       "#{User.count} users, #{Prediction.count} predictions " \
       "(#{Prediction.scored.count} scored), #{ChampionPick.count} champion picks."
end

puts
puts "== Login credentials =="
puts "  Admin: admin@pitchpredict.app / worldcup2026"
puts "  Demo:  demo@pitchpredict.app  / worldcup2026"
