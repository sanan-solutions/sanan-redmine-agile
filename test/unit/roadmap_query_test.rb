# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class RoadmapQueryTest < ActiveSupport::TestCase
  include SananRoadmapTestHelper
  fixtures(*ROADMAP_FIXTURES)

  def setup
    User.current = User.find(1)
    @project = enable_roadmap!
  end

  def query(year = 2026)
    SananAgile::RoadmapQuery.new(@project, cfg: roadmap_cfg, year: year).call
  end

  def test_planned_epic_lands_in_its_quarter_with_story_progress
    epic = create_epic!
    # Open story first: Redmine derives the parent status, so a lone closed child would close the Epic.
    create_story!(epic)
    create_story!(epic, closed: true)
    plan!(epic, 2026, 2, health: 'at_risk')

    row = query[:quarters][2].detect { |e| e[:id] == epic.id }
    assert row
    assert_equal 'at_risk', row[:health]
    assert_equal 2, row[:story_count]
    assert_equal 1, row[:done_count]
    assert_equal 50, row[:progress] # no SP → share of closed stories
  end

  def test_unplanned_lists_open_epics_only
    open_epic = create_epic!(subject: 'Open')
    closed_epic = create_epic!(subject: 'Closed')
    closed_epic.update_column(:status_id, 5)

    ids = query[:unplanned].map { |e| e[:id] }
    assert_includes ids, open_epic.id
    assert_not_includes ids, closed_epic.id
  end

  def test_epic_planned_in_another_year_is_not_shown_but_indexed
    epic = create_epic!
    plan!(epic, 2027, 1)

    data = query(2026)
    assert data[:quarters].values.flatten.none? { |e| e[:id] == epic.id }
    assert data[:unplanned].none? { |e| e[:id] == epic.id }
    assert_equal 2027, data[:all_epics][epic.id][:year]
  end

  def test_move_history_counts_slips_and_keeps_origin
    epic = create_epic!
    plan!(epic, 2026, 3)
    [[nil, nil, 2026, 1], [2026, 1, 2026, 2], [2026, 2, 2026, 3]].each do |fy, fq, ty, tq|
      SananRoadmapMove.create!(project_id: @project.id, issue_id: epic.id, from_year: fy, from_quarter: fq,
                               to_year: ty, to_quarter: tq, created_at: Time.now)
    end

    moves = query[:quarters][3].detect { |e| e[:id] == epic.id }[:moves]
    assert_equal 3, moves[:count]
    assert_equal 2, moves[:slips]
    assert_equal 'Q1/2026', moves[:origin]
    assert moves[:slipped]
  end

  def test_not_slipped_when_back_at_the_origin_quarter
    epic = create_epic!
    plan!(epic, 2026, 1)
    [[2026, 1, 2026, 3], [2026, 3, 2026, 1]].each do |fy, fq, ty, tq|
      SananRoadmapMove.create!(project_id: @project.id, issue_id: epic.id, from_year: fy, from_quarter: fq,
                               to_year: ty, to_quarter: tq, created_at: Time.now)
    end

    moves = query[:quarters][1].first[:moves]
    assert_equal 1, moves[:slips]
    assert_not moves[:slipped]
  end

  def test_origin_is_the_starting_quarter_when_history_begins_mid_plan
    epic = create_epic!
    plan!(epic, 2027, 1)
    SananRoadmapMove.create!(project_id: @project.id, issue_id: epic.id, from_year: 2026, from_quarter: 4,
                             to_year: 2027, to_quarter: 1, created_at: Time.now)

    assert_equal 'Q4/2026', query(2027)[:quarters][1].first[:moves][:origin]
  end

  def test_destroying_an_epic_removes_its_roadmap_rows
    epic = create_epic!
    plan!(epic, 2026, 1)
    SananRoadmapMove.create!(project_id: @project.id, issue_id: epic.id, to_year: 2026, to_quarter: 1,
                             created_at: Time.now)
    epic.destroy

    assert_equal 0, SananRoadmapItem.where(issue_id: epic.id).count
    assert_equal 0, SananRoadmapMove.where(issue_id: epic.id).count
  end

  def test_epic_carries_its_priority_for_the_icon
    epic = create_epic!
    epic.update_column(:priority_id, IssuePriority.find_by(name: 'Urgent')&.id || IssuePriority.first.id)
    row = query[:unplanned].detect { |e| e[:id] == epic.id }
    assert_equal epic.reload.priority.name, row[:priority]
    assert_equal SananAgile::PriorityIcon.key(epic.priority), row[:priority_key]
  end

  def test_progress_shows_ready_to_release_and_development_done
    dod = IssueCustomField.create!(name: 'DoD sprint', field_format: 'string', is_for_all: true, tracker_ids: [1])
    uat = IssueCustomField.create!(name: 'UAT done sprint', field_format: 'string', is_for_all: true, tracker_ids: [1])
    enable_roadmap!(@project, 'dod_cfid' => dod.id.to_s, 'uat_done_cfid' => uat.id.to_s,
                              'progress_excluded_status_ids' => ['6'], 'agile_board_group_uat_status_ids' => ['4'])
    @project.reload
    epic = create_epic!
    open_story = create_story!(epic)                                                 # nothing done
    create_story!(epic).tap { |s| s.update_column(:status_id, 4) }                   # in the UAT phase: dev done
    create_story!(epic).tap { |s| s.custom_field_values = { dod.id.to_s => 'S1' }; s.save! } # DoD: dev done
    create_story!(epic).tap { |s| s.custom_field_values = { uat.id.to_s => 'S1' }; s.save! } # passed UAT: ready
    create_story!(epic).tap { |s| s.update_column(:status_id, 6) }                   # Rejected: left out
    plan!(epic, 2026, 2)

    row = query[:quarters][2].detect { |e| e[:id] == epic.id }
    assert_equal 4, row[:story_count]   # the rejected one is not counted
    assert_equal 1, row[:done_count]
    assert_equal 3, row[:dev_count]
    assert_equal 25, row[:progress]     # ready to release
    assert_equal 75, row[:dev_progress] # development done
    assert open_story
  end
end
