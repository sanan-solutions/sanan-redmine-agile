# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# Commit = standard ticket on the sprint with a "This sprint" SP for at least one part, whatever its status.
class SprintCommitTest < ActiveSupport::TestCase
  include SananRoadmapTestHelper
  fixtures(*ROADMAP_FIXTURES)

  def setup
    User.current = User.find(1)
    @project = Project.find(1)
    @be, @fe, @qa = %w[BE FE QA].map do |n|
      IssueCustomField.create!(name: "SP #{n} sprint", field_format: 'float', is_for_all: true, tracker_ids: [1, 2, 3])
    end
    enable_roadmap!(@project, 'sp_be_cfid' => @be.id.to_s, 'sp_fe_cfid' => @fe.id.to_s, 'sp_qa_cfid' => @qa.id.to_s,
                              'standard_tracker' => %w[1 2], 'subtask_tracker' => ['3'], 'epic_tracker' => '',
                              'commit_dev_status_ids' => %w[1 2])
    @sprint = Version.create!(project: @project, name: 'Sprint C', status: 'open')
  end

  def cfg
    SananAgile::ProjectSettings.load(@project.id)
  end

  def ticket(status_id: 1, tracker_id: 1, sp: {})
    values = sp.to_h { |part, v| [{ be: @be, fe: @fe, qa: @qa }[part].id.to_s, v.to_s] }
    Issue.create!(project: @project, tracker_id: tracker_id, author_id: 2, subject: 'T', status_id: status_id,
                  fixed_version: @sprint, priority: IssuePriority.first, custom_field_values: values)
  end

  def test_ticket_with_sprint_sp_is_committed_whatever_its_status
    dev_only = ticket(sp: { be: 3 })
    done = ticket(status_id: 5, sp: { fe: 2 })      # closed: dev done during the sprint
    uat = ticket(status_id: 3, sp: { qa: 1 })       # outside set A (e.g. UAT), test committed
    ids = SananAgile::SprintCommit.issue_ids(@sprint, cfg)
    assert_equal [dev_only.id, done.id, uat.id].sort, ids.sort
    assert SananAgile::SprintCommit.committed?(done.reload, cfg)
  end

  def test_ticket_without_sprint_sp_is_not_committed
    carried = ticket(status_id: 3) # e.g. waiting for UAT, no work this sprint
    assert_not_includes SananAgile::SprintCommit.issue_ids(@sprint, cfg), carried.id
    assert_not SananAgile::SprintCommit.committed?(carried, cfg)
  end

  def test_sprint_total_alone_also_commits
    t = ticket
    SananIssueSprintSp.create!(issue_id: t.id, version_id: @sprint.id, sp_total: 3, captured_at: Time.now)
    assert_includes SananAgile::SprintCommit.issue_ids(@sprint, cfg), t.id
  end

  def test_subtask_tracker_is_never_committed
    sub = ticket(tracker_id: 3, sp: { be: 2 })
    assert_not_includes SananAgile::SprintCommit.issue_ids(@sprint, cfg), sub.id
  end

  def test_committed_ids_among_issues
    a = ticket(sp: { be: 1 })
    b = ticket
    assert_equal [a.id], SananAgile::SprintCommit.committed_ids_among([a, b], cfg)
  end

  def test_legacy_status_rule_without_team_sp
    enable_roadmap!(@project, 'standard_tracker' => %w[1 2], 'commit_dev_status_ids' => %w[1 2])
    in_dev = ticket(status_id: 2)
    in_uat = ticket(status_id: 3)
    ids = SananAgile::SprintCommit.issue_ids(@sprint, cfg)
    assert_includes ids, in_dev.id
    assert_not_includes ids, in_uat.id
  end

  def test_closed_sprint_commit_counts_moved_tickets_from_history_not_removed_ones
    stays = ticket(status_id: 5, sp: { be: 3 })
    moved = ticket(sp: { fe: 2 })
    removed = ticket(sp: { qa: 5 })
    other = Version.create!(project: @project, name: 'Sprint D', status: 'open')
    # removed during the sprint: history row for this sprint, no longer on it before close
    removed.reload.update!(fixed_version: other)

    @sprint.update!(status: 'closed') # Closer snapshots the commit set before anything moves on
    snapshot = @sprint.reload.sanan_agile_version_meta.commit_issue_ids_list
    assert_equal [stays.id, moved.id].sort, snapshot.sort

    moved.reload.update!(fixed_version: other) # moved on at Complete: sprint SP cleared, kept in history
    assert_equal '', moved.reload.custom_field_value(@fe).to_s

    report = SananAgile::SprintReport::Calculator.call(@sprint.reload, cfg: cfg, prefer_snapshot: false)
    assert_equal [3.0, 2.0, 0.0], [report.commit_be, report.commit_fe, report.commit_qa]
    assert_equal 5.0, report.commit_sp
  end
end
