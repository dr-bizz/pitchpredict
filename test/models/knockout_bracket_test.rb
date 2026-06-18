require "test_helper"

class KnockoutBracketTest < ActiveSupport::TestCase
  test "defines exactly 32 knockout matches" do
    assert_equal 32, KnockoutBracket.specs.size
  end

  test "match numbers are 73..104, contiguous and unique" do
    numbers = KnockoutBracket.specs.map { |s| s[:match_number] }
    assert_equal (73..104).to_a, numbers.sort
  end

  test "each stage has the right number of matches" do
    counts = KnockoutBracket.specs.group_by { |s| s[:stage] }.transform_values(&:size)
    assert_equal({ r32: 16, r16: 8, qf: 4, sf: 2, third_place: 1, final: 1 }, counts)
  end

  test "R32 labels cover every group winner and runner-up plus eight thirds" do
    labels = KnockoutBracket.specs.select { |s| s[:stage] == :r32 }
                            .flat_map { |s| [ s[:home_label], s[:away_label] ] }
    %w[A B C D E F G H I J K L].each do |g|
      assert_includes labels, "Winner Group #{g}"
      assert_includes labels, "Runner-up Group #{g}"
    end
    assert_equal 8, labels.count { |l| l.start_with?("3rd Place") }
  end

  test "later-round labels only reference real earlier match numbers" do
    numbers = KnockoutBracket.specs.map { |s| s[:match_number] }.to_set
    KnockoutBracket.specs.each do |spec|
      [ spec[:home_label], spec[:away_label] ].each do |label|
        if (m = label.match(/Match (\d+)/))
          referenced = m[1].to_i
          assert_includes numbers, referenced, "#{label} references missing match #{referenced}"
          assert referenced < spec[:match_number], "#{label} must reference an earlier match"
        end
      end
    end
  end

  test "for returns the spec by stage and zero-based index" do
    assert_equal 73, KnockoutBracket.for(:r32, 0)[:match_number]
    assert_equal 88, KnockoutBracket.for(:r32, 15)[:match_number]
    assert_equal 104, KnockoutBracket.for(:final, 0)[:match_number]
    assert_nil KnockoutBracket.for(:r32, 99)
  end
end
