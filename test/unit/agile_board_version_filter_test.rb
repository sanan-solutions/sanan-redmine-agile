# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class AgileBoardVersionFilterTest < ActiveSupport::TestCase
  include SananRoadmapTestHelper
  fixtures(*ROADMAP_FIXTURES)

  def setup
    @project = Project.find(1)
    enable_roadmap!(@project)
    SananAgile::AgileDataAssociation.ensure!
    @open = Version.create!(project: @project, name: 'Sprint open', status: 'open')
    @closed = Version.create!(project: @project, name: 'Sprint closed', status: 'closed')
    User.current = User.find(1)
  end

  def version_ids(query)
    query.available_filters['fixed_version_id'][:values].map { |v| v[1].to_s }
  end

  def test_closed_versions_are_not_offered
    ids = version_ids(AgileQuery.new(project: @project))
    assert_includes ids, @open.id.to_s
    assert_not_includes ids, @closed.id.to_s
  end

  def test_a_selected_closed_version_stays_offered
    query = AgileQuery.new(project: @project)
    query.add_filter('fixed_version_id', '=', [@closed.id.to_s])
    assert_includes version_ids(query), @closed.id.to_s
  end

  def test_hidden_trackers_are_left_out_of_the_board
    enable_roadmap!(@project, 'agile_board_hidden_tracker_ids' => ['', EPIC_TRACKER_ID.to_s])
    query = AgileQuery.new(project: @project)
    tracker_ids = query.issues.map(&:tracker_id).uniq
    assert_not_includes tracker_ids, EPIC_TRACKER_ID
    assert_includes tracker_ids, STORY_TRACKER_ID
  end
end
