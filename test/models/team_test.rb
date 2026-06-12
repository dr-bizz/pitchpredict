require "test_helper"

class TeamTest < ActiveSupport::TestCase
  test "valid with name, uppercase 3-letter code and group A-L" do
    team = Team.new(name: "Argentina", code: "ARG", group_name: "D")
    assert team.valid?
  end

  test "rejects lowercase, wrong-length and duplicate codes" do
    assert_not Team.new(name: "X", code: "arg", group_name: "A").valid?
    assert_not Team.new(name: "X", code: "ARGY", group_name: "A").valid?
    assert_not Team.new(name: "X", code: teams(:spain).code, group_name: "A").valid?
  end

  test "rejects group outside A-L" do
    assert_not Team.new(name: "X", code: "XYZ", group_name: "M").valid?
  end
end
