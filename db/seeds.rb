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
#     the host stadiums, and the real fixture schedule on its true calendar
#     dates (matches already kicked off are locked, awaiting results an admin
#     enters). Set SCHEDULE_LEAD_DAYS to instead shift the whole schedule into
#     the future so every match is open on a fresh game. NO demo accounts are
#     created. A single admin is created from ADMIN_EMAIL / ADMIN_PASSWORD; if
#     ADMIN_PASSWORD is unset a random one is generated and printed once.
#
# NOTE: these seeds are a DESTRUCTIVE REBUILD (db:seed:replant style): every run
# wipes all rows (including users and their sessions) and recreates the world.
#
# NOTE: the 48 teams, the 12 groups (A–L) AND the full group-stage schedule
# (matchups, dates, kickoff slots and host venues) are the REAL official
# tournament data (Final Draw 5 Dec 2025). Only the knockout pairings are
# illustrative — the qualifiers are unknown, so the bracket uses placeholders.
# Production mirrors the real calendar by default; set SCHEDULE_LEAD_DAYS to
# shift the whole schedule into the future for a fresh game where every match is
# open to predict.
#
# Kickoff times are stored/created in Eastern (config.time_zone), the app's
# display zone, rounded to the published slot and kept on each match's real
# calendar date.
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

# The real groups from the official Final Draw (Washington, DC, 5 Dec 2025).
TEAMS_BY_GROUP = {
  "A" => [ [ "Mexico", "MEX", "🇲🇽", "CONCACAF" ], [ "South Korea", "KOR", "🇰🇷", "AFC" ],
          [ "Czechia", "CZE", "🇨🇿", "UEFA" ], [ "South Africa", "RSA", "🇿🇦", "CAF" ] ],
  "B" => [ [ "Canada", "CAN", "🇨🇦", "CONCACAF" ], [ "Switzerland", "SUI", "🇨🇭", "UEFA" ],
          [ "Qatar", "QAT", "🇶🇦", "AFC" ], [ "Bosnia and Herzegovina", "BIH", "🇧🇦", "UEFA" ] ],
  "C" => [ [ "Brazil", "BRA", "🇧🇷", "CONMEBOL" ], [ "Morocco", "MAR", "🇲🇦", "CAF" ],
          [ "Scotland", "SCO", "🏴󠁧󠁢󠁳󠁣󠁴󠁿", "UEFA" ], [ "Haiti", "HAI", "🇭🇹", "CONCACAF" ] ],
  "D" => [ [ "United States", "USA", "🇺🇸", "CONCACAF" ], [ "Paraguay", "PAR", "🇵🇾", "CONMEBOL" ],
          [ "Australia", "AUS", "🇦🇺", "AFC" ], [ "Türkiye", "TUR", "🇹🇷", "UEFA" ] ],
  "E" => [ [ "Germany", "GER", "🇩🇪", "UEFA" ], [ "Ecuador", "ECU", "🇪🇨", "CONMEBOL" ],
          [ "Ivory Coast", "CIV", "🇨🇮", "CAF" ], [ "Curaçao", "CUW", "🇨🇼", "CONCACAF" ] ],
  "F" => [ [ "Netherlands", "NED", "🇳🇱", "UEFA" ], [ "Japan", "JPN", "🇯🇵", "AFC" ],
          [ "Sweden", "SWE", "🇸🇪", "UEFA" ], [ "Tunisia", "TUN", "🇹🇳", "CAF" ] ],
  "G" => [ [ "Belgium", "BEL", "🇧🇪", "UEFA" ], [ "Egypt", "EGY", "🇪🇬", "CAF" ],
          [ "Iran", "IRN", "🇮🇷", "AFC" ], [ "New Zealand", "NZL", "🇳🇿", "OFC" ] ],
  "H" => [ [ "Spain", "ESP", "🇪🇸", "UEFA" ], [ "Uruguay", "URU", "🇺🇾", "CONMEBOL" ],
          [ "Saudi Arabia", "KSA", "🇸🇦", "AFC" ], [ "Cape Verde", "CPV", "🇨🇻", "CAF" ] ],
  "I" => [ [ "France", "FRA", "🇫🇷", "UEFA" ], [ "Senegal", "SEN", "🇸🇳", "CAF" ],
          [ "Norway", "NOR", "🇳🇴", "UEFA" ], [ "Iraq", "IRQ", "🇮🇶", "AFC" ] ],
  "J" => [ [ "Argentina", "ARG", "🇦🇷", "CONMEBOL" ], [ "Austria", "AUT", "🇦🇹", "UEFA" ],
          [ "Algeria", "ALG", "🇩🇿", "CAF" ], [ "Jordan", "JOR", "🇯🇴", "AFC" ] ],
  "K" => [ [ "Portugal", "POR", "🇵🇹", "UEFA" ], [ "Colombia", "COL", "🇨🇴", "CONMEBOL" ],
          [ "Uzbekistan", "UZB", "🇺🇿", "AFC" ], [ "DR Congo", "COD", "🇨🇩", "CAF" ] ],
  "L" => [ [ "England", "ENG", "🏴󠁧󠁢󠁥󠁮󠁧󠁿", "UEFA" ], [ "Croatia", "CRO", "🇭🇷", "UEFA" ],
          [ "Ghana", "GHA", "🇬🇭", "CAF" ], [ "Panama", "PAN", "🇵🇦", "CONCACAF" ] ]
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

# Champion-pick contenders — all present in the real draw above (no Italy: they
# did not qualify for 2026).
CONTENDER_CODES = %w[BRA FRA ARG ESP ENG GER POR NED BEL URU].freeze

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
  # Each spec: { home:, away:, stadium:, kickoff:, stage: }. We adjust the actual
  # kickoff per profile (demo keeps real dates; production shifts the whole set).
  specs = []
  team_by_code = Team.all.index_by(&:code)
  kickoff_hours = [ 16, 19, 22 ] # ET — used only by the illustrative knockout bracket

  # The real World Cup 2026 group stage: [home code, away code, [month, day, hour,
  # minute] ET, stadium index]. Stadium indices match the STADIUMS array above.
  group_schedule = [
    # Group A
    [ "MEX", "RSA", [ 6, 11, 15, 0 ], 0 ], [ "KOR", "CZE", [ 6, 11, 20, 0 ], 1 ],
    [ "CZE", "RSA", [ 6, 18, 12, 0 ], 9 ], [ "MEX", "KOR", [ 6, 18, 23, 0 ], 1 ],
    [ "MEX", "CZE", [ 6, 24, 21, 0 ], 0 ], [ "RSA", "KOR", [ 6, 24, 21, 0 ], 2 ],
    # Group B
    [ "CAN", "BIH", [ 6, 12, 18, 0 ], 3 ], [ "SUI", "QAT", [ 6, 13, 15, 0 ], 13 ],
    [ "CAN", "QAT", [ 6, 18, 18, 0 ], 4 ], [ "BIH", "SUI", [ 6, 18, 15, 0 ], 6 ],
    [ "SUI", "CAN", [ 6, 24, 15, 0 ], 4 ], [ "QAT", "BIH", [ 6, 24, 15, 0 ], 12 ],
    # Group C
    [ "BRA", "MAR", [ 6, 13, 18, 0 ], 5 ], [ "HAI", "SCO", [ 6, 13, 15, 0 ], 14 ],
    [ "BRA", "HAI", [ 6, 19, 21, 0 ], 11 ], [ "SCO", "MAR", [ 6, 19, 18, 0 ], 14 ],
    [ "SCO", "BRA", [ 6, 24, 18, 0 ], 10 ], [ "MAR", "HAI", [ 6, 24, 18, 0 ], 9 ],
    # Group D
    [ "USA", "PAR", [ 6, 12, 21, 0 ], 6 ], [ "AUS", "TUR", [ 6, 13, 21, 0 ], 4 ],
    [ "USA", "AUS", [ 6, 19, 15, 0 ], 12 ], [ "TUR", "PAR", [ 6, 19, 22, 0 ], 13 ],
    [ "TUR", "USA", [ 6, 25, 22, 0 ], 6 ], [ "PAR", "AUS", [ 6, 25, 22, 0 ], 13 ],
    # Group E
    [ "GER", "CUW", [ 6, 14, 15, 0 ], 8 ], [ "CIV", "ECU", [ 6, 14, 19, 0 ], 11 ],
    [ "GER", "CIV", [ 6, 20, 16, 0 ], 3 ], [ "ECU", "CUW", [ 6, 20, 20, 0 ], 15 ],
    [ "ECU", "GER", [ 6, 25, 16, 0 ], 5 ], [ "CUW", "CIV", [ 6, 25, 16, 0 ], 11 ],
    # Group F
    [ "NED", "JPN", [ 6, 14, 16, 0 ], 7 ], [ "SWE", "TUN", [ 6, 14, 22, 0 ], 2 ],
    [ "NED", "SWE", [ 6, 20, 13, 0 ], 8 ], [ "TUN", "JPN", [ 6, 20, 22, 0 ], 2 ],
    [ "JPN", "SWE", [ 6, 25, 19, 0 ], 7 ], [ "TUN", "NED", [ 6, 25, 19, 0 ], 15 ],
    # Group G
    [ "BEL", "EGY", [ 6, 15, 18, 0 ], 12 ], [ "IRN", "NZL", [ 6, 15, 21, 0 ], 6 ],
    [ "BEL", "IRN", [ 6, 21, 15, 0 ], 6 ], [ "NZL", "EGY", [ 6, 21, 21, 0 ], 4 ],
    [ "EGY", "IRN", [ 6, 26, 23, 0 ], 12 ], [ "NZL", "BEL", [ 6, 26, 23, 0 ], 4 ],
    # Group H
    [ "ESP", "CPV", [ 6, 15, 12, 0 ], 9 ], [ "KSA", "URU", [ 6, 15, 18, 0 ], 10 ],
    [ "ESP", "KSA", [ 6, 21, 12, 0 ], 9 ], [ "URU", "CPV", [ 6, 21, 18, 0 ], 10 ],
    [ "CPV", "KSA", [ 6, 26, 20, 0 ], 8 ], [ "URU", "ESP", [ 6, 26, 20, 0 ], 1 ],
    # Group I
    [ "FRA", "SEN", [ 6, 16, 15, 0 ], 5 ], [ "IRQ", "NOR", [ 6, 16, 18, 0 ], 14 ],
    [ "FRA", "IRQ", [ 6, 22, 17, 0 ], 11 ], [ "NOR", "SEN", [ 6, 22, 20, 0 ], 5 ],
    [ "NOR", "FRA", [ 6, 26, 15, 0 ], 14 ], [ "SEN", "IRQ", [ 6, 26, 15, 0 ], 3 ],
    # Group J
    [ "ARG", "ALG", [ 6, 16, 21, 0 ], 15 ], [ "AUT", "JOR", [ 6, 16, 22, 0 ], 13 ],
    [ "ARG", "AUT", [ 6, 22, 13, 0 ], 7 ], [ "JOR", "ALG", [ 6, 22, 23, 0 ], 13 ],
    [ "ALG", "AUT", [ 6, 27, 22, 0 ], 15 ], [ "JOR", "ARG", [ 6, 27, 22, 0 ], 7 ],
    # Group K
    [ "POR", "COD", [ 6, 17, 13, 0 ], 8 ], [ "UZB", "COL", [ 6, 17, 22, 0 ], 0 ],
    [ "POR", "UZB", [ 6, 23, 13, 0 ], 8 ], [ "COL", "COD", [ 6, 23, 22, 0 ], 1 ],
    [ "COL", "POR", [ 6, 27, 19, 30 ], 10 ], [ "COD", "UZB", [ 6, 27, 19, 30 ], 9 ],
    # Group L
    [ "ENG", "CRO", [ 6, 17, 16, 0 ], 7 ], [ "GHA", "PAN", [ 6, 17, 19, 0 ], 3 ],
    [ "ENG", "GHA", [ 6, 23, 16, 0 ], 14 ], [ "PAN", "CRO", [ 6, 23, 19, 0 ], 3 ],
    [ "PAN", "ENG", [ 6, 27, 17, 0 ], 5 ], [ "CRO", "GHA", [ 6, 27, 17, 0 ], 11 ]
  ]

  group_schedule.each_with_index do |(home_code, away_code, (mon, day, hr, min), stadium_idx), idx|
    kickoff = Time.zone.local(2026, mon, day, hr, min)
    specs << { home: team_by_code.fetch(home_code), away: team_by_code.fetch(away_code),
               stadium: stadiums[stadium_idx], kickoff:, stage: :group, match_number: idx + 1 }
  end

  # Knockout fixtures — qualifiers are unknown, so teams are nil and each slot
  # carries a descriptive label from KnockoutBracket. The schedule (dates,
  # stadiums) is fixed; an admin fills in teams as the bracket is announced.
  knockout_stadium = ->(i) { stadiums[i % stadiums.length] }
  ko = ->(stage, index, stadium, kickoff) do
    spec = KnockoutBracket.for(stage, index)
    { home: nil, away: nil, stadium:, kickoff:, stage:,
      home_label: spec[:home_label], away_label: spec[:away_label],
      match_number: spec[:match_number] }
  end

  16.times do |i| # Round of 32: June 28 – July 3
    kickoff = Time.zone.local(2026, 6, 28, kickoff_hours[i % 3]) + (i / 3).days
    specs << ko.call(:r32, i, knockout_stadium.call(i), kickoff)
  end
  8.times do |j| # Round of 16: July 4 – 7
    kickoff = Time.zone.local(2026, 7, 4, kickoff_hours[j % 3]) + (j / 2).days
    specs << ko.call(:r16, j, knockout_stadium.call(j + 3), kickoff)
  end
  4.times do |k| # Quarter-finals: July 9 – 10
    kickoff = Time.zone.local(2026, 7, 9, kickoff_hours[k % 2]) + (k / 2).days
    specs << ko.call(:qf, k, knockout_stadium.call(k + 6), kickoff)
  end
  2.times do |s| # Semi-finals: July 14 – 15
    kickoff = Time.zone.local(2026, 7, 14, 19) + s.days
    specs << ko.call(:sf, s, knockout_stadium.call(s + 10), kickoff)
  end
  specs << ko.call(:third_place, 0, stadiums[10], Time.zone.local(2026, 7, 18, 19))
  specs << ko.call(:final, 0, stadiums[5], Time.zone.local(2026, 7, 19, 19))

  # By default the schedule mirrors the REAL tournament calendar (offset 0).
  # Optionally set SCHEDULE_LEAD_DAYS to shift the whole schedule forward so the
  # earliest match kicks off that many days from now — a "fresh game" where every
  # fixture is open to predict regardless of the real date. Demo always keeps the
  # real dates (and backdates/scores the past matches below).
  lead_days = ENV["SCHEDULE_LEAD_DAYS"].presence&.to_i
  earliest = specs.map { |s| s[:kickoff] }.min
  offset = (SEED_DEMO || lead_days.nil?) ? 0.seconds : ((NOW + lead_days.days) - earliest)

  puts "== Fixtures (#{specs.size}) =="
  real_kickoffs = {}
  group_fixtures = []
  specs.each do |spec|
    kickoff = spec[:kickoff] + offset
    # Demo mode temporarily floats past kickoffs into the future so predictions
    # can be created before results exist; production kickoffs are all future.
    provisional = (SEED_DEMO && kickoff <= NOW) ? kickoff + 60.days : kickoff
    fixture = Fixture.create!(home_team: spec[:home], away_team: spec[:away],
                              stadium: spec[:stadium], kickoff_at: provisional, stage: spec[:stage],
                              home_slot_label: spec[:home_label], away_slot_label: spec[:away_label],
                              match_number: spec[:match_number])
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
