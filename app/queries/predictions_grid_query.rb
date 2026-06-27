# Builds the predictions grid from two independent, combinable axes:
#
#   status — all / upcoming / unpredicted / predicted / past (filters membership)
#   stage  — all / group / r32 / … / final                  (filters + groups)
#
# Returns an ordered list of Sections (heading + fixtures) so the view stays
# free of grouping logic. Day-grouped results tag their past sections so the
# view can drop a "Kicked off" divider at the upcoming→past boundary.
class PredictionsGridQuery
  Section = Data.define(:heading, :fixtures, :past)

  STATUSES = %w[all upcoming unpredicted predicted past].freeze

  def initialize(user:, status:, stage:)
    @user = user
    @status = status
    @stage = stage
  end

  def sections
    @sections ||= grouped(scoped).reject { |section| section.fixtures.empty? }
  end

  # Flat list of every rendered fixture — lets the controller preload the
  # current user's predictions in one query, avoiding an N+1 in the cards.
  def fixtures
    sections.flat_map(&:fixtures)
  end

  private

  def scoped
    rel = Fixture.includes(:home_team, :away_team, :stadium)
    rel = rel.by_stage(@stage) unless @stage == "all"
    apply_status(rel)
  end

  def apply_status(rel)
    case @status
    when "upcoming"
      rel.where(kickoff_at: Time.current..)
    when "past"
      rel.where(kickoff_at: ...Time.current)
    when "unpredicted"
      # Open to predict (teams set, scheduled, not locked) and not yet picked.
      rel.where(kickoff_at: Time.current..).scheduled.teams_set
         .where.not(id: @user.predictions.select(:fixture_id))
    when "predicted"
      rel.where(id: @user.predictions.select(:fixture_id))
    else # "all"
      rel
    end
  end

  def grouped(rel)
    case @stage
    when "all"
      by_day(rel)
    when "group"
      by_group_letter(rel)
    else
      by_match_number(rel)
    end
  end

  # Group stage: a section per group letter, ordered A→Z, matches in fixture
  # order within. Assumption (as elsewhere): both teams in a group fixture share
  # the home team's group_name.
  def by_group_letter(rel)
    rel.order(:match_number, :kickoff_at).group_by { |f| f.home_team.group_name }
       .sort_by(&:first)
       .map { |letter, day| Section.new(heading: "Group #{letter}", fixtures: day, past: false) }
  end

  # A single knockout stage: one bracket-ordered section, no day headers.
  def by_match_number(rel)
    [ Section.new(heading: nil, fixtures: rel.order(:match_number, :kickoff_at).to_a, past: false) ]
  end

  # Upcoming soonest-first, then past most-recent-first, each split into a
  # section per calendar day (in the app's display zone, so day headers match
  # the card times). Past sections are tagged for the "Kicked off" divider.
  def by_day(rel)
    fixtures = rel.to_a
    upcoming = fixtures.select { |f| f.kickoff_at >= Time.current }.sort_by(&:kickoff_at)
    past = (fixtures - upcoming).sort_by(&:kickoff_at).reverse
    day_sections(upcoming, past: false) + day_sections(past, past: true)
  end

  def day_sections(fixtures, past:)
    fixtures.group_by { |f| f.kickoff_at.in_time_zone.to_date }.map do |date, day|
      Section.new(heading: date.strftime("%A %-d %B"), fixtures: day, past: past)
    end
  end
end
