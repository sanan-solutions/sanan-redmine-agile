# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class RoadmapCapacityTest < ActiveSupport::TestCase
  include SananRoadmapTestHelper
  fixtures(*ROADMAP_FIXTURES)

  def setup
    User.current = User.find(1)
    @project = enable_roadmap!
  end

  def capacity(year:, today:, extra_cfg: {})
    SananAgile::RoadmapCapacity.new(@project, cfg: roadmap_cfg.merge(extra_cfg), year: year, today: today).call
  end

  def test_past_quarters_have_no_capacity_and_current_counts_from_today
    cap = capacity(year: 2026, today: Date.new(2026, 10, 3))
    assert cap[:quarters][1][:past]
    assert cap[:quarters][3][:past]
    refute cap[:quarters][4][:past]
    # 2026-10-03 .. 2026-12-31 = 90 days / 14-day sprints
    assert_in_delta 6.4, cap[:quarters][4][:sprints], 0.05
  end

  def test_future_year_counts_full_quarters
    cap = capacity(year: 2027, today: Date.new(2026, 10, 3))
    assert(cap[:quarters].values.none? { |q| q[:past] })
    assert_in_delta 90.0 / 14, cap[:quarters][1][:sprints], 0.05
  end

  def test_no_closed_sprints_means_no_velocity
    Version.where(project_id: @project.id).update_all(status: 'open')
    cap = capacity(year: 2027, today: Date.new(2026, 10, 3))
    assert_equal 0, cap[:sample_size]
    assert_equal 0, cap[:velocity]
    assert_equal 0, cap[:quarters][1][:capacity]
  end

  def test_window_setting_defaults_to_five
    assert_equal 5, SananAgile::RoadmapCapacity.window_from({})
    assert_equal 3, SananAgile::RoadmapCapacity.window_from('roadmap_capacity_window' => '3')
    assert_equal 5, SananAgile::RoadmapCapacity.window_from('roadmap_capacity_window' => '7')
  end

  def test_members_are_project_members_with_their_role
    cap = capacity(year: 2027, today: Date.new(2026, 10, 3))
    jsmith = cap[:members].detect { |m| m[:id] == 2 }
    assert jsmith
    assert_equal 'Manager', jsmith[:role]
    assert_equal 'JS', jsmith[:initials]
  end
end
