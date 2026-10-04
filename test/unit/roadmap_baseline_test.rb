# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class RoadmapBaselineTest < ActiveSupport::TestCase
  include SananRoadmapTestHelper
  fixtures(*ROADMAP_FIXTURES)

  def setup
    User.current = User.find(1)
    @project = enable_roadmap!
  end

  def review(year = 2026, quarter = 2)
    data = SananAgile::RoadmapQuery.new(@project, cfg: roadmap_cfg, year: year).call
    baseline = SananRoadmapBaseline.find_by!(project_id: @project.id, year: year, quarter: quarter)
    SananAgile::RoadmapBaseline.review(baseline, data)
  end

  def state_of(rev, epic)
    rev[:epics].detect { |r| r[:id] == epic.id }[:state]
  end

  def test_review_classifies_plan_against_actual
    kept = create_epic!(subject: 'Kept')
    done = create_epic!(subject: 'Done')
    slipped = create_epic!(subject: 'Slipped')
    dropped = create_epic!(subject: 'Dropped')
    [kept, done, slipped, dropped].each { |e| plan!(e, 2026, 2) }

    SananAgile::RoadmapBaseline.capture!(@project, year: 2026, quarter: 2, user: User.find(2), cfg: roadmap_cfg)

    done.update_column(:status_id, 5)
    SananRoadmapItem.find_by(issue_id: slipped.id).update!(quarter: 3)
    SananRoadmapItem.where(issue_id: dropped.id).delete_all
    added = create_epic!(subject: 'Added')
    plan!(added, 2026, 2)

    rev = review
    assert_equal 'in_progress', state_of(rev, kept)
    assert_equal 'done', state_of(rev, done)
    assert_equal 'slipped', state_of(rev, slipped)
    assert_equal 'dropped', state_of(rev, dropped)
    assert_equal 'added', state_of(rev, added)
    assert_equal 4, rev[:summary][:committed_epics]
    assert_equal 1, rev[:summary][:counts]['added']
    assert_equal 'Q3/2026', rev[:epics].detect { |r| r[:id] == slipped.id }[:now_in]
  end

  def test_epic_with_all_stories_closed_counts_as_done
    epic = create_epic!
    create_story!(epic, closed: true)
    plan!(epic, 2026, 2)
    SananAgile::RoadmapBaseline.capture!(@project, year: 2026, quarter: 2, user: User.find(2), cfg: roadmap_cfg)

    assert_equal 'done', state_of(review, epic)
  end

  def test_capture_again_replaces_the_baseline
    first = create_epic!(subject: 'First')
    plan!(first, 2026, 2)
    SananAgile::RoadmapBaseline.capture!(@project, year: 2026, quarter: 2, user: User.find(2), cfg: roadmap_cfg)
    second = create_epic!(subject: 'Second')
    plan!(second, 2026, 2)
    SananAgile::RoadmapBaseline.capture!(@project, year: 2026, quarter: 2, user: User.find(2), cfg: roadmap_cfg)

    assert_equal 1, SananRoadmapBaseline.where(project_id: @project.id, year: 2026, quarter: 2).count
    assert_equal [first.id, second.id].sort, review[:epics].map { |r| r[:id] }.sort
    assert review[:epics].none? { |r| r[:state] == 'added' }
  end
end
