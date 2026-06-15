# PitchPredict seed data — World Cup 2026.
#
# Two seed profiles, chosen automatically:
#
#   * DEMO  (development/test, or production with SEED_DEMO=true) — a fully
#     populated showcase: ~14 players with a spread of predictions, champion
#     picks, and roughly half the group stage already played and scored so the
#     leaderboard shows real numbers. The admin + a demo player use the
#     well-known password "worldcup2026".
#
#   * PRODUCTION (default in production) — reference data only: all 48 teams,
#     the host stadiums, and the full fixture list shifted into the future so
#     every match is open for predictions on a fresh game. NO demo accounts are
#     created. A single admin is created from ADMIN_EMAIL / ADMIN_PASSWORD; if
#     ADMIN_PASSWORD is unset a random one is generated and printed once.
#
# NOTE: these seeds are a DESTRUCTIVE REBUILD (db:seed:replant style): every run
# wipes all rows (including users and their sessions) and recreates the world.
#
# NOTE: group draws, knockout pairings and (in demo mode) results are
# illustrative, not the real 2026 draw. Teams are real, plausible qualifiers
# with correct FIFA codes. Replace the fixture list with the official schedule
# for a real game.
#
# Seeding strategy (demo mode): Prediction and ChampionPick carry kickoff-lock
# validations, so we seed in two phases. Phase 1 creates every fixture with a
# provisional *future* kickoff (past kickoffs temporarily shifted +60 days),
# then creates predictions and champion picks while the tournament is still
# "open". Phase 2 backdates the past fixtures to their real kickoff, records
# final scores, marks them finished and runs ScoringService.score_fixture! on
# each. Nothing is saved with `validate: false`.

require "securerandom"

RNG = Random.new(2026) # deterministic results on every replant
NOW = Time.current

# Demo profile: everywhere except production, unless explicitly requested.
SEED_DEMO = !Rails.env.production? || ENV["SEED_DEMO"] == "true"

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

generated_admin_password = nil

puts "== Clearing existing data (destructive replant) =="
puts "== Profile: #{SEED_DEMO ? 'DEMO (populated showcase)' : 'PRODUCTION (reference data only)'} =="
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

  # ---- Build the fixture schedule as plain specs first -----------------------
  # Each spec: { home:, away:, stadium:, kickoff:, stage: } with the illustrative
  # (shifted ~10 days early) kickoff. We adjust the actual kickoff per profile.
  specs = []
  kickoff_hours = [ 16, 19, 22 ] # UTC

  # Group stage round-robin: matchdays 1/2/3 start June 1 / 9 / 17, staggered by
  # group so kickoffs spread across 2026-06-01..2026-06-24.
  group_pairings = [ [ 0, 1 ], [ 2, 3 ], [ 0, 2 ], [ 1, 3 ], [ 0, 3 ], [ 1, 2 ] ]
  matchday_start_day = [ 1, 9, 17 ]
  teams_by_group.values.each_with_index do |teams, g_index|
    group_pairings.each_with_index do |(h, a), m_index|
      day = matchday_start_day[m_index / 2] + (g_index % 8)
      kickoff = Time.zone.local(2026, 6, day, kickoff_hours[(g_index + m_index) % 3])
      stadium = stadiums[((g_index * 6) + m_index) % stadiums.length]
      specs << { home: teams[h], away: teams[a], stadium:, kickoff:, stage: :group }
    end
  end

  # Knockout placeholders — illustrative bracket: group winners (12) +
  # runners-up (12) + 8 "best third-placed" teams (groups A–H here).
  winners = teams_by_group.values.map { |t| t[0] }
  runners = teams_by_group.values.map { |t| t[1] }
  thirds  = teams_by_group.values.first(8).map { |t| t[2] }
  bracket = winners + runners + thirds # 32 teams
  knockout_stadium = ->(i) { stadiums[i % stadiums.length] }

  16.times do |i| # Round of 32: June 28 – July 3
    kickoff = Time.zone.local(2026, 6, 28, kickoff_hours[i % 3]) + (i / 3).days
    specs << { home: bracket[i], away: bracket[31 - i], stadium: knockout_stadium.call(i), kickoff:, stage: :r32 }
  end
  8.times do |j| # Round of 16: July 4 – 7
    kickoff = Time.zone.local(2026, 7, 4, kickoff_hours[j % 3]) + (j / 2).days
    specs << { home: bracket[2 * j], away: bracket[(2 * j) + 1], stadium: knockout_stadium.call(j + 3), kickoff:, stage: :r16 }
  end
  4.times do |k| # Quarter-finals: July 9 – 10
    kickoff = Time.zone.local(2026, 7, 9, kickoff_hours[k % 2]) + (k / 2).days
    specs << { home: bracket[4 * k], away: bracket[(4 * k) + 2], stadium: knockout_stadium.call(k + 6), kickoff:, stage: :qf }
  end
  2.times do |s| # Semi-finals: July 14 – 15
    kickoff = Time.zone.local(2026, 7, 14, 19) + s.days
    specs << { home: bracket[8 * s], away: bracket[(8 * s) + 4], stadium: knockout_stadium.call(s + 10), kickoff:, stage: :sf }
  end
  specs << { home: bracket[4], away: bracket[12], stadium: stadiums[10], kickoff: Time.zone.local(2026, 7, 18, 19), stage: :third_place }
  specs << { home: bracket[0], away: bracket[8], stadium: stadiums[5], kickoff: Time.zone.local(2026, 7, 19, 19), stage: :final }

  # In production, shift the whole illustrative schedule forward so the earliest
  # match kicks off ~3 days from now — every fixture is open for a fresh game.
  earliest = specs.map { |s| s[:kickoff] }.min
  offset = SEED_DEMO ? 0.seconds : ((NOW + 3.days) - earliest)

  puts "== Fixtures (#{specs.size}) =="
  real_kickoffs = {}
  group_fixtures = []
  specs.each do |spec|
    kickoff = spec[:kickoff] + offset
    # Demo mode temporarily floats past kickoffs into the future so predictions
    # can be created before results exist; production kickoffs are all future.
    provisional = (SEED_DEMO && kickoff <= NOW) ? kickoff + 60.days : kickoff
    fixture = Fixture.create!(home_team: spec[:home], away_team: spec[:away],
                              stadium: spec[:stadium], kickoff_at: provisional, stage: spec[:stage])
    real_kickoffs[fixture] = kickoff
    group_fixtures << fixture if spec[:stage] == :group
  end

  # ---- Admin (always) --------------------------------------------------------
  puts "== Admin =="
  if SEED_DEMO
    admin_email = "admin@pitchpredict.app"
    admin_password = "worldcup2026"
  else
    admin_email = ENV.fetch("ADMIN_EMAIL", "admin@pitchpredict.app")
    admin_password = ENV["ADMIN_PASSWORD"].presence || (generated_admin_password = SecureRandom.base58(16))
  end
  User.create!(name: "Tournament Admin", email_address: admin_email,
               password: admin_password, password_confirmation: admin_password, role: :admin)

  finished = 0
  if SEED_DEMO
    # ---- Demo players --------------------------------------------------------
    puts "== Demo players =="
    password = "worldcup2026"
    demo = User.create!(name: "Dani Demo", email_address: "demo@pitchpredict.app",
                        password:, password_confirmation: password, role: :player)
    players = [ demo ] + PLAYER_NAMES.map.with_index do |name, i|
      User.create!(name:, email_address: "player#{i + 1}@pitchpredict.app",
                   password:, password_confirmation: password, role: :player)
    end

    # ---- Predictions + champion picks (while every fixture is still open) ----
    puts "== Predictions and champion picks =="
    contenders = CONTENDER_CODES.map { |code| Team.find_by!(code:) }
    players.each do |player|
      coverage = RNG.rand(0.60..1.0) # each player predicts 60–100% of group games
      group_fixtures.sample((group_fixtures.size * coverage).round, random: RNG).each do |fixture|
        player.predictions.create!(fixture:, home_score: random_goals, away_score: random_goals)
      end
      player.create_champion_pick!(team: contenders.sample(random: RNG))
    end

    # ---- Backdate past fixtures, record results, score -----------------------
    puts "== Results for fixtures already played =="
    real_kickoffs.each do |fixture, kickoff|
      next unless kickoff <= NOW

      fixture.update!(kickoff_at: kickoff, status: :finished,
                      home_score: random_goals, away_score: random_goals)
      ScoringService.score_fixture!(fixture)
      finished += 1
    end
  end

  puts "Seeded: #{Team.count} teams, #{Stadium.count} stadiums, " \
       "#{Fixture.count} fixtures (#{finished} finished), " \
       "#{User.count} users, #{Prediction.count} predictions " \
       "(#{Prediction.scored.count} scored), #{ChampionPick.count} champion picks."
end

puts
if SEED_DEMO
  puts "== Login credentials =="
  puts "  Admin: admin@pitchpredict.app / worldcup2026"
  puts "  Demo:  demo@pitchpredict.app  / worldcup2026"
else
  puts "== Admin login =="
  admin_email = ENV.fetch("ADMIN_EMAIL", "admin@pitchpredict.app")
  if generated_admin_password
    puts "  Email:    #{admin_email}"
    puts "  Password: #{generated_admin_password}"
    puts "  ^ Generated — save it now; it is not shown again. Set ADMIN_PASSWORD to choose your own."
  else
    puts "  Email:    #{admin_email}"
    puts "  Password: (the ADMIN_PASSWORD you provided)"
  end
end
