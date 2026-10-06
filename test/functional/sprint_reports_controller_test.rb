# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class SprintReportsControllerTest < Redmine::ControllerTest
  include SananRoadmapTestHelper
  fixtures(*ROADMAP_FIXTURES)

  def setup
    @project = Project.find(1)
    @be, @fe = %w[BE FE].map do |n|
      IssueCustomField.create!(name: "SP #{n} sprint", field_format: 'float', is_for_all: true, tracker_ids: [1])
    end
    @done_be = IssueCustomField.create!(name: 'Done BE in sprint', field_format: 'version', is_for_all: true,
                                        tracker_ids: [1])
    enable_roadmap!(@project, 'sp_be_cfid' => @be.id.to_s, 'sp_fe_cfid' => @fe.id.to_s,
                              'done_be_cfid' => @done_be.id.to_s, 'standard_tracker' => ['1'])
    Role.find(1).add_permission!(:view_sprint_reports)
    @sprint = Version.create!(project: @project, name: 'Sprint R', status: 'open')
    Issue.create!(project: @project, tracker_id: 1, author_id: 2, subject: 'BE only', status_id: 1,
                  fixed_version: @sprint, priority: IssuePriority.first,
                  custom_field_values: { @be.id.to_s => '4', @done_be.id.to_s => @sprint.id.to_s })
    @request.session[:user_id] = 2
  end

  def test_qa_sp_counts_when_done_qa_in_sprint_is_this_sprint
    qa = IssueCustomField.create!(name: 'SP QA sprint', field_format: 'float', is_for_all: true, tracker_ids: [1])
    done_qa = IssueCustomField.create!(name: 'Done QA in sprint', field_format: 'version', is_for_all: true,
                                       tracker_ids: [1])
    enable_roadmap!(@project, 'sp_be_cfid' => @be.id.to_s, 'sp_fe_cfid' => @fe.id.to_s, 'sp_qa_cfid' => qa.id.to_s,
                              'done_be_cfid' => @done_be.id.to_s, 'done_qa_cfid' => done_qa.id.to_s,
                              'standard_tracker' => ['1'])
    @project.reload # its custom field list was cached before the QA fields existed
    Issue.create!(project: @project, tracker_id: 1, author_id: 2, subject: 'QA only', status_id: 1,
                  fixed_version: @sprint, priority: IssuePriority.first,
                  custom_field_values: { qa.id.to_s => '2', done_qa.id.to_s => @sprint.id.to_s })

    report = SananAgile::SprintReport::Calculator.call(@sprint, cfg: SananAgile::ProjectSettings.load(@project.id))
    assert_equal 2.0, report.actual_qa
    assert_equal 2.0, report.commit_qa

    get :show, params: { project_id: @project.identifier, id: @sprint.id }
    assert_response :success
    assert_select '#sr-commit-tickets td', text: /Done\s*·\s*2\s*SP/
  end

  def test_legacy_development_done_setting_is_read_as_done_qa
    qa = IssueCustomField.create!(name: 'SP QA sprint', field_format: 'float', is_for_all: true, tracker_ids: [1])
    dev_done = IssueCustomField.create!(name: 'Done QA In Sprint (workflow)', field_format: 'version',
                                        is_for_all: true, tracker_ids: [1])
    enable_roadmap!(@project, 'sp_qa_cfid' => qa.id.to_s, 'done_qa_cfid' => '',
                              'development_done_cfid' => dev_done.id.to_s, 'standard_tracker' => ['1'])
    @project.reload
    Issue.create!(project: @project, tracker_id: 1, author_id: 2, subject: 'QA via workflow field', status_id: 1,
                  fixed_version: @sprint, priority: IssuePriority.first,
                  custom_field_values: { qa.id.to_s => '3', dev_done.id.to_s => @sprint.id.to_s })

    report = SananAgile::SprintReport::Calculator.call(@sprint, cfg: SananAgile::ProjectSettings.load(@project.id))
    assert_equal 3.0, report.actual_qa
  end

  def test_report_shows_part_percentages_and_dod_sp
    get :show, params: { project_id: @project.identifier, id: @sprint.id }
    assert_response :success
    assert_select '.sr-kpi__pct', text: /100%/            # BE: 4 done / 4 committed
    assert_select '.sr-kpi--total .sr-kpi__label', text: I18n.t(:label_sprint_report_dod_sp)
    assert_select '#sr-commit-tickets h3', text: /\(1\)/   # the BE-only ticket is committed
  end

  def test_committed_part_not_done_shows_commit_cell_and_is_not_summed
    Issue.create!(project: @project, tracker_id: 1, author_id: 2, subject: 'FE committed', status_id: 1,
                  fixed_version: @sprint, priority: IssuePriority.first,
                  custom_field_values: { @fe.id.to_s => '3' })

    get :show, params: { project_id: @project.identifier, id: @sprint.id }
    assert_response :success
    assert_select '#sr-commit-tickets .sr-code-flag--plan', text: /Commit\s*·\s*3\s*SP/
    assert_select '#sr-commit-tickets tfoot th', text: /\A0\s*SP\z/ # FE footer: nothing done
  end

  def test_moved_ticket_uses_this_sprint_history_not_its_new_sprint_value
    next_sprint = Version.create!(project: @project, name: 'Sprint R+1', status: 'open')
    moved = Issue.create!(project: @project, tracker_id: 1, author_id: 2, subject: 'Moved on', status_id: 1,
                          fixed_version: next_sprint, priority: IssuePriority.first,
                          custom_field_values: { @be.id.to_s => '8', @done_be.id.to_s => @sprint.id.to_s })
    SananIssueSprintSp.create!(issue_id: moved.id, version_id: @sprint.id, sp_be: 5, captured_at: Time.current)

    report = SananAgile::SprintReport::Calculator.call(@sprint, cfg: SananAgile::ProjectSettings.load(@project.id))
    assert_equal 9.0, report.actual_be # 4 (still here) + 5 (history), not 4 + 8
  end

  def with_settings(extra)
    enable_roadmap!(@project, SananAgile::ProjectSettings.load(@project.id).merge(extra))
    @project.reload
  end

  def test_part_without_sprint_sp_counts_zero_not_size
    size_be = IssueCustomField.create!(name: 'Size BE', field_format: 'float', is_for_all: true, tracker_ids: [1])
    with_settings('size_be_cfid' => size_be.id.to_s)
    Issue.create!(project: @project, tracker_id: 1, author_id: 2, subject: 'Sized only', status_id: 1,
                  fixed_version: @sprint, priority: IssuePriority.first,
                  custom_field_values: { @done_be.id.to_s => @sprint.id.to_s, size_be.id.to_s => '6' })

    report = SananAgile::SprintReport::Calculator.call(@sprint, cfg: SananAgile::ProjectSettings.load(@project.id))
    assert_equal 4.0, report.actual_be
  end

  def test_sprint_total_commit_not_dod_shows_commit_cell_and_is_not_summed
    total = IssueCustomField.create!(name: 'SP sprint Total', field_format: 'float', is_for_all: true, tracker_ids: [1])
    with_settings('sp_sprint_total_cfid' => total.id.to_s)
    Issue.create!(project: @project, tracker_id: 1, author_id: 2, subject: 'Total only', status_id: 1,
                  fixed_version: @sprint, priority: IssuePriority.first, custom_field_values: { total.id.to_s => '5' })

    get :show, params: { project_id: @project.identifier, id: @sprint.id }
    assert_response :success
    assert_select '#sr-commit-tickets .sr-code-flag--plan', text: /Commit\s*·\s*5\s*SP/
    assert_select '#sr-commit-tickets tfoot th[title]', text: /\A0\s*SP\z/ # nothing reached DoD
  end
end
