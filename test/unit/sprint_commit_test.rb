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
                              'standard_tracker' => %w[1 2], 'subtask_tracker' => ['3'], 'epic_tracker' => '')
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
    uat = ticket(status_id: 3, sp: { qa: 1 })       # e.g. UAT, test committed
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

  def test_without_team_sp_every_standard_ticket_on_the_sprint_counts
    enable_roadmap!(@project, 'standard_tracker' => %w[1 2])
    a = ticket(status_id: 2)
    b = ticket(status_id: 3)
    assert_equal [a.id, b.id].sort, SananAgile::SprintCommit.issue_ids(@sprint, cfg).sort
    assert SananAgile::SprintCommit.committed?(b, cfg)
    assert_not SananAgile::SprintCommit.enabled?(cfg) # no commit tracking without "This sprint" SP fields
  end

  def test_story_points_column_is_the_sprint_total_not_the_size
    enable_roadmap!(@project, SananAgile::ProjectSettings.load(@project.id).merge('sp_total_formula' => 'max',
                                                                                    'sp_total_require_qa' => '0'))
    with_total = ticket(sp: { be: 1 })
    SananIssueSprintSp.create!(issue_id: with_total.id, version_id: @sprint.id, sp_total: 5, captured_at: Time.now)
    from_parts = ticket(sp: { be: 3, fe: 2 }) # no sprint Total: formula max(BE, FE, QA)

    report = SananAgile::SprintReport::Calculator.call(@sprint, cfg: cfg)
    rows = report.coded_issues.index_by { |r| r.issue.id }
    assert_equal 5.0, rows[with_total.id].sp
    assert_equal 3.0, rows[from_parts.id].sp
    assert_equal 8.0, report.commit_sp # = sum of the column
  end

  def test_sprint_sp_counts_only_dod_tickets
    dod_cf = IssueCustomField.create!(name: 'DoD sprint', field_format: 'version', is_for_all: true, tracker_ids: [1, 2])
    enable_roadmap!(@project, SananAgile::ProjectSettings.load(@project.id).merge(
      'dod_cfid' => dod_cf.id.to_s, 'sp_total_formula' => 'max', 'sp_total_require_qa' => '0'))
    @project.reload
    done = Issue.create!(project: @project, tracker_id: 1, author_id: 2, subject: 'DoD', status_id: 1,
                         fixed_version: @sprint, priority: IssuePriority.first,
                         custom_field_values: { @be.id.to_s => '3', dod_cf.id.to_s => @sprint.id.to_s })
    ticket(sp: { fe: 5 }) # committed, not DoD

    report = SananAgile::SprintReport::Calculator.call(@sprint, cfg: cfg)
    assert_equal 3.0, report.actual_sp                       # only the DoD ticket's sprint SP
    assert_equal 8.0, report.commit_sp                       # all committed tickets
    rows = report.coded_issues.select(&:committed)
    assert_equal 3.0, rows.select(&:dod).sum(&:sp)           # table total
    assert_includes rows.select(&:dod).map { |r| r.issue.id }, done.id
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
    # Commit SP = sum of each ticket's sprint SP (formula over its sprint parts when no Total is set)
    expected = SananAgile::SpTotalFormula.resolve(3, nil, nil, nil, cfg: cfg).to_f +
               SananAgile::SpTotalFormula.resolve(nil, 2, nil, nil, cfg: cfg).to_f
    assert_equal expected, report.commit_sp
  end
end
