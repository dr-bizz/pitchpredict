require "test_helper"

class UserPredictionsHelperTest < ActionView::TestCase
  test "tabs start with Past and drop the editable Upcoming tab" do
    tabs = UserPredictionsHelper::PREDICTION_TABS
    assert_equal "past", tabs.keys.first
    assert_equal "Past", tabs.values.first
    refute_includes tabs.keys, "upcoming"
    assert_includes tabs.keys, "group"
    assert_includes tabs.keys, "final"
  end

  test "outcome label maps points to its tier, nil for unknown" do
    assert_equal "Exact", prediction_outcome_label(ScoringService::EXACT_POINTS)
    assert_equal "Diff", prediction_outcome_label(ScoringService::DIFFERENCE_POINTS)
    assert_equal "Tendency", prediction_outcome_label(ScoringService::TENDENCY_POINTS)
    assert_equal "Miss", prediction_outcome_label(0)
    assert_nil prediction_outcome_label(5)
    assert_nil prediction_outcome_label(nil)
  end
end
