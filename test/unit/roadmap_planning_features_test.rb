# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# Dependencies, multi-quarter Epics and health suggestions.
class RoadmapPlanningFeaturesTest < ActiveSupport::TestCase
  include SananRoadmapTestHelper
  fixtures(*ROADMAP_FIXTURES)

  def setup
    User.current = User.find(1)
    @project = enable_roadmap!
  end

  def query(year = 2026, today: Date.new(2026, 5, 15), project: @project)
    SananAgile::RoadmapQuery.new(project, cfg: roadmap_cfg(project), year: year, today: today).call
  end

  def epic_data(epic, year = 2026, **opts)
    query(year, **opts)[:all_epics][epic.id]
  end

  def relate!(from, to, type = IssueRelation::TYPE_BLOCKS)
    IssueRelation.create!(issue_from: from, issue_to: to, relation_type: type)
  end

  # --- dependencies

  def test_blocker_planned_later_is_a_conflict
    blocker = create_epic!(subject: 'Blocker')
    dependent = create_epic!(subject: 'Dependent')
    plan!(blocker, 2026, 3)
    plan!(dependent, 2026, 2)
    relate!(blocker, dependent)

    dep = epic_data(dependent)
    assert_equal [blocker.id], dep[:depends_on].map { |d| d[:id] }
    assert dep[:depends_on].first[:conflict]
    assert dep[:dep_conflict]
    assert epic_data(blocker)[:blocking].first[:conflict]
  end

  def test_blocker_in_same_or_earlier_quarter_is_fine
    blocker = create_epic!(subject: 'Blocker')
    dependent = create_epic!(subject: 'Dependent')
    plan!(blocker, 2026, 2)
    plan!(dependent, 2026, 2)
    relate!(blocker, dependent, IssueRelation::TYPE_PRECEDES)

    refute epic_data(dependent)[:dep_conflict]
  end

  def test_unplanned_open_blocker_is_a_conflict_closed_one_is_not
    blocker = create_epic!(subject: 'Blocker')
    dependent = create_epic!(subject: 'Dependent')
    plan!(dependent, 2026, 2)
    relate!(blocker, dependent)
    assert epic_data(dependent)[:dep_conflict]

    blocker.update_column(:status_id, 5)
    refute epic_data(dependent)[:dep_conflict]
  end

  def test_story_relations_roll_up_to_epics_across_projects
    other = enable_roadmap!(Project.find(2))
    epic_a = create_epic!(@project, subject: 'A')
    epic_b = create_epic!(other, subject: 'B')
    story_a = create_story!(epic_a)
    story_b = Issue.create!(project: other, tracker_id: STORY_TRACKER_ID, author_id: 2, subject: 'Story B',
                            parent_issue_id: epic_b.id, status_id: 1, priority: IssuePriority.first)
    plan!(epic_a, 2026, 2)
    plan!(epic_b, 2026, 4)
    with_settings cross_project_issue_relations: '1' do
      relate!(story_b, story_a) # B's story blocks A's story ⇒ Epic A depends on Epic B
    end

    dep = epic_data(epic_a)[:depends_on].first
    assert_equal epic_b.id, dep[:id]
    assert_equal other.name, dep[:project]
    assert dep[:conflict]
  end

  # --- multi-quarter Epics

  def test_span_creates_continuations_in_later_quarters
    epic = create_epic!
    item = plan!(epic, 2026, 2)
    item.span = 3
    item.save!

    data = query
    assert_equal [epic.id], data[:quarters][2].map { |e| e[:id] }
    assert_equal [epic.id], data[:continuations][3].map { |c| c[:id] }
    assert_equal [epic.id], data[:continuations][4].map { |c| c[:id] }
    assert_empty data[:continuations][1]
    assert_equal 3, data[:all_epics][epic.id][:span]
  end

  def test_span_crossing_into_next_year_continues_there
    epic = create_epic!
    item = plan!(epic, 2026, 4)
    item.span = 2
    item.save!

    data = query(2027)
    assert_equal [epic.id], data[:continuations][1].map { |c| c[:id] }
    refute data[:continuations][1].first[:in_data]
    assert_equal [2027, 1], [item.reload.end_year, item.end_quarter]
  end

  def test_span_is_limited_and_validated
    epic = create_epic!
    item = plan!(epic, 2026, 1)
    item.span = 9
    assert_equal 4, item.span
    item.end_year = 2025
    item.end_quarter = 4
    assert_not item.valid?
  end

  # --- health suggestion

  def test_suggests_off_track_when_quarter_is_over
    epic = create_epic!
    create_story!(epic)
    plan!(epic, 2026, 1)
    assert_equal 'off_track', epic_data(epic)[:suggestion][:health]
  end

  def test_suggests_by_pace_inside_the_quarter
    epic = create_epic!
    create_story!(epic)
    plan!(epic, 2026, 2)
    # 2026-06-20: ~90% of Q2 elapsed, 0% done
    assert_equal 'off_track', epic_data(epic, today: Date.new(2026, 6, 20))[:suggestion][:health]
    # 2026-04-05: ~5% elapsed
    assert_equal 'on_track', epic_data(epic, today: Date.new(2026, 4, 5))[:suggestion][:health]
  end

  def test_blocked_story_suggests_at_risk
    blocked = IssueStatus.create!(name: 'Blocked', is_closed: false)
    epic = create_epic!
    story = create_story!(epic)
    story.update_column(:status_id, blocked.id)
    plan!(epic, 2026, 3)
    suggestion = epic_data(epic)[:suggestion]
    assert_equal 'at_risk', suggestion[:health]
    assert_equal 1, suggestion[:reasons].size
  end

  def test_configured_blocked_statuses_replace_the_name_match
    waiting = IssueStatus.create!(name: 'Waiting for vendor', is_closed: false)
    enable_roadmap!(@project, 'roadmap_blocked_status_ids' => [waiting.id.to_s])
    epic = create_epic!
    story = create_story!(epic)
    story.update_column(:status_id, waiting.id)
    plan!(epic, 2026, 3)
    assert_equal 'at_risk', epic_data(epic)[:suggestion][:health]

    blocked = IssueStatus.create!(name: 'Blocked', is_closed: false)
    story.update_column(:status_id, blocked.id) # name matches, but not configured
    assert_equal 'on_track', epic_data(epic)[:suggestion][:health]
  end

  def test_portfolio_board_resolves_dependencies_once
    enable_roadmap!(Project.find(2))
    plan!(create_epic!(@project), 2026, 2)
    plan!(create_epic!(Project.find(2)), 2026, 2)
    relation_queries = 0
    counter = ->(*, payload) { relation_queries += 1 if payload[:sql].to_s.include?('issue_relations') }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
      board = SananAgile::RoadmapProduct.board([@project, Project.find(2)], year: 2026, user: User.find(1),
                                                                          today: Date.new(2026, 5, 15))
      assert_equal 2, board[:products].size
    end
    assert_equal 1, relation_queries
  end

  def test_no_suggestion_for_unplanned_epic
    epic = create_epic!
    assert_nil epic_data(epic)[:suggestion]
  end
end
