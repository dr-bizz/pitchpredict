# Single source of truth for the knockout-stage topology. The qualifiers are
# unknown until the group stage ends, so each slot carries a descriptive LABEL
# (e.g. "Winner Group A", "Winner of Match 89") rather than a team. The match
# numbers and the match-to-match feeding form a clean, internally consistent
# single-elimination tree (the actual group pairings are illustrative).
#
# Pure data + lookup — no database access — so it is safe to use from seeds, a
# data migration, and unit tests alike.
module KnockoutBracket
  GROUPS = %w[A B C D E F G H I J K L].freeze

  # R32 slot labels, in the same pairing order the seeds build (home bracket[i]
  # vs away bracket[31-i], where bracket = winners(0-11) + runners(12-23) +
  # thirds(24-31)). Index 0..15 -> match numbers 73..88.
  R32 = begin
    winners = GROUPS.map { |g| "Winner Group #{g}" }
    runners = GROUPS.map { |g| "Runner-up Group #{g}" }
    thirds  = GROUPS.first(8).map { |g| "3rd Place — Group #{g}" }
    bracket = winners + runners + thirds # 32 labels
    (0..15).map { |i| { home_label: bracket[i], away_label: bracket[31 - i] } }
  end.freeze

  def self.specs
    @specs ||= build.freeze
  end

  # The index-th (0-based) match of a stage, matching the seed loop counters.
  def self.for(stage, index)
    by_stage_index[[ stage.to_sym, index ]]
  end

  def self.build
    rows = []
    R32.each_with_index { |labels, i| rows << { stage: :r32, match_number: 73 + i, **labels } }

    # Each round pairs the winners of two consecutive earlier matches.
    pair = ->(stage, base, count, src_start) do
      count.times do |n|
        rows << {
          stage: stage, match_number: base + n,
          home_label: "Winner of Match #{src_start + (2 * n)}",
          away_label: "Winner of Match #{src_start + (2 * n) + 1}"
        }
      end
    end
    pair.call(:r16, 89, 8, 73) # R16 89..96 from R32 73..88
    pair.call(:qf,  97, 4, 89) # QF  97..100 from R16 89..96
    pair.call(:sf, 101, 2, 97) # SF  101..102 from QF 97..100

    rows << { stage: :third_place, match_number: 103,
              home_label: "Loser of Match 101", away_label: "Loser of Match 102" }
    rows << { stage: :final, match_number: 104,
              home_label: "Winner of Match 101", away_label: "Winner of Match 102" }
    rows
  end

  def self.by_stage_index
    @by_stage_index ||= specs
      .group_by { |s| s[:stage] }
      .flat_map { |stage, list| list.each_with_index.map { |s, i| [[ stage, i ], s] } }
      .to_h
  end

  private_class_method :build, :by_stage_index
end
