# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# Complete sprint: open tickets move to the next sprint — DoD-reached ones too (the DoD field keeps
# the sprint where DoD was reached).
class BacklogCompleteSprintTest < Redmine::ControllerTest
  include SananRoadmapTestHelper
  tests BacklogsController
  fixtures(*ROADMAP_FIXTURES)

  def setup
    @project = Project.find(1)
    @dod_cf = IssueCustomField.create!(name: 'DoD In Sprint', field_format: 'string', is_for_all: true,
                                       tracker_ids: [1, 2, 3])
    enable_roadmap!(@project, 'backlog_enabled' => '1', 'dod_cfid' => @dod_cf.id.to_s,
                              'dod_checkbox_statuses' => ['2'], 'standard_tracker' => ['1'])
    Role.find(1).add_permission!(:view_backlog, :manage_backlog, :manage_versions)
    @sprint = Version.create!(project: @project, name: 'Sprint A', status: 'open', effective_date: Date.today)
    @next = Version.create!(project: @project, name: 'Sprint B', status: 'open')
    @request.session[:user_id] = 2
  end

  def ticket(status_id, subject, cf_values = {})
    Issue.create!(project: @project, tracker_id: 1, author_id: 2, subject: subject, status_id: status_id,
                  fixed_version: @sprint, priority: IssuePriority.default || IssuePriority.first,
                  custom_field_values: cf_values)
  end

  def test_dod_ticket_moves_to_next_sprint_and_keeps_dod_sprint
    dod = ticket(2, 'DoD reached, waiting UAT')
    open = ticket(1, 'Not done')
    post :complete_sprint, params: { project_id: @project.identifier, version_id: @sprint.id,
                                     dod_confirmed: '1', dod_issue_ids: [dod.id], move_unfinished_to: @next.id }
    assert_response :redirect
    assert_equal 'closed', @sprint.reload.status
    assert_equal @next.id, dod.reload.fixed_version_id
    assert_equal 'Sprint A', dod.custom_field_value(@dod_cf)
    assert_equal @next.id, open.reload.fixed_version_id
  end

  def test_closed_ticket_stays_in_the_completed_sprint
    done = ticket(5, 'Closed')
    post :complete_sprint, params: { project_id: @project.identifier, version_id: @sprint.id,
                                     move_unfinished_to: @next.id }
    assert_equal @sprint.id, done.reload.fixed_version_id
  end

  def test_dod_candidates_skip_tickets_already_dod_in_another_sprint
    @project.reload
    earlier = ticket(2, 'DoD last sprint, UAT here', @dod_cf.id.to_s => 'Sprint 0')
    fresh = ticket(2, 'Reached DoD here')

    ids = SananAgile::DodSprint.complete_candidate_ids(@sprint, roadmap_cfg(@project))
    assert_equal [fresh.id], ids

    post :complete_sprint, params: { project_id: @project.identifier, version_id: @sprint.id,
                                     dod_confirmed: '1', dod_issue_ids: [earlier.id, fresh.id],
                                     move_unfinished_to: @next.id }
    assert_equal 'Sprint 0', earlier.reload.custom_field_value(@dod_cf)
    assert_equal 'Sprint A', fresh.reload.custom_field_value(@dod_cf)
  end

  def test_dod_candidates_are_only_committed_tickets
    sp_be = IssueCustomField.create!(name: 'SP BE sprint', field_format: 'float', is_for_all: true, tracker_ids: [1])
    enable_roadmap!(@project, 'backlog_enabled' => '1', 'dod_cfid' => @dod_cf.id.to_s, 'sp_be_cfid' => sp_be.id.to_s,
                              'dod_checkbox_statuses' => ['2'], 'standard_tracker' => ['1'])
    @project.reload
    committed = Issue.create!(project: @project, tracker_id: 1, author_id: 2, subject: 'Committed', status_id: 2,
                              fixed_version: @sprint, priority: IssuePriority.first,
                              custom_field_values: { sp_be.id.to_s => '3' })
    ticket(2, 'Not committed')

    assert_equal [committed.id], SananAgile::DodSprint.complete_candidate_ids(@sprint, roadmap_cfg(@project))
  end
end
