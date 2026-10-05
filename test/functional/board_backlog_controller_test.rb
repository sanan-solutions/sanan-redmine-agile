# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class BoardBacklogControllerTest < Redmine::ControllerTest
  include SananRoadmapTestHelper
  tests SananAgile::BoardBacklogController
  fixtures(*ROADMAP_FIXTURES)

  def setup
    @project = Project.find(1)
    @be = IssueCustomField.create!(name: 'SP BE sprint', field_format: 'float', is_for_all: true, tracker_ids: [1])
    @qa = IssueCustomField.create!(name: 'SP QA sprint', field_format: 'float', is_for_all: true, tracker_ids: [1])
    @sprint = Version.create!(project: @project, name: 'Board sprint', status: 'open')
    @next = Version.create!(project: @project, name: 'Next sprint', status: 'open', effective_date: Date.today + 30)
    enable_roadmap!(@project, 'backlog_enabled' => '1', 'agile_board_backlog_enabled' => '1',
                              'standard_tracker' => ['1'], 'sp_be_cfid' => @be.id.to_s,
                              'sp_qa_cfid' => @qa.id.to_s)
    @project.reload
    Role.find(1).add_permission!(:view_backlog, :manage_backlog)
    @request.session[:user_id] = 2
    @backlog_issue = Issue.create!(project: @project, tracker_id: 1, author_id: 2, subject: 'In backlog',
                                   status_id: 1, priority: IssuePriority.first)
    @next_issue = Issue.create!(project: @project, tracker_id: 1, author_id: 2, subject: 'In next sprint',
                                status_id: 1, priority: IssuePriority.first, fixed_version: @next)
  end

  def json
    JSON.parse(response.body)
  end

  def test_index_lists_backlog_and_upcoming_sprints
    get :index, params: { project_id: @project.identifier, target_version_id: @sprint.id }
    assert_response :success
    ids = json['issues'].map { |i| i['id'] }
    assert_includes ids, @backlog_issue.id
    assert_not_includes ids, @next_issue.id
    assert_equal %w[sp_parts], json['issues'].first.keys & %w[sp_parts]
    sources = json['sources'].map { |s| s['value'] }
    assert_equal 'backlog', sources.first
    assert_includes sources, @next.id.to_s
    assert_not_includes sources, @sprint.id.to_s # the board's own sprint

    get :index, params: { project_id: @project.identifier, source: @next.id, target_version_id: @sprint.id }
    assert_equal [@next_issue.id], json['issues'].map { |i| i['id'] }
  end

  def test_pull_moves_ticket_into_sprint_and_column_with_sprint_sp
    post :pull, params: { project_id: @project.identifier, issue_id: @backlog_issue.id, version_id: @sprint.id,
                          status_id: 2, sp: { be: '3' } }
    assert_response :success
    @backlog_issue.reload
    assert_equal @sprint.id, @backlog_issue.fixed_version_id
    assert_equal 2, @backlog_issue.status_id
    assert_equal '3', @backlog_issue.custom_field_value(@be)
    cfg = SananAgile::ProjectSettings.load(@project.id)
    assert SananAgile::SprintCommit.committed?(@backlog_issue, cfg)
  end

  def test_pull_without_sp_joins_the_sprint_uncommitted
    post :pull, params: { project_id: @project.identifier, issue_id: @next_issue.id, version_id: @sprint.id,
                          status_id: 1 }
    assert_response :success
    @next_issue.reload
    assert_equal @sprint.id, @next_issue.fixed_version_id
    assert_not SananAgile::SprintCommit.committed?(@next_issue, SananAgile::ProjectSettings.load(@project.id))
  end

  def test_pull_rejects_a_status_the_workflow_does_not_allow
    WorkflowTransition.where(tracker_id: 1, old_status_id: 1, new_status_id: 4).delete_all
    post :pull, params: { project_id: @project.identifier, issue_id: @backlog_issue.id, version_id: @sprint.id,
                          status_id: 4 }
    assert_response :unprocessable_entity
    assert_nil @backlog_issue.reload.fixed_version_id
  end

  def test_pull_needs_manage_backlog
    Role.find(1).remove_permission!(:manage_backlog)
    post :pull, params: { project_id: @project.identifier, issue_id: @backlog_issue.id, version_id: @sprint.id,
                          status_id: 1 }
    assert_response :forbidden
  end

  def test_push_returns_a_board_ticket_to_the_backlog_and_clears_its_sprint_sp
    issue = Issue.create!(project: @project, tracker_id: 1, author_id: 2, subject: 'On the board', status_id: 2,
                          priority: IssuePriority.first, fixed_version: @sprint,
                          custom_field_values: { @be.id.to_s => '5' })
    post :push, params: { project_id: @project.identifier, issue_id: issue.id, source: 'backlog' }
    assert_response :success
    issue.reload
    assert_nil issue.fixed_version_id
    assert_equal 2, issue.status_id
    assert_equal '', issue.custom_field_value(@be).to_s
    assert_equal 5.0, SananIssueSprintSp.find_by(issue_id: issue.id, version_id: @sprint.id).sp_be.to_f
  end

  def test_push_into_another_sprint
    issue = Issue.create!(project: @project, tracker_id: 1, author_id: 2, subject: 'On the board', status_id: 1,
                          priority: IssuePriority.first, fixed_version: @sprint)
    post :push, params: { project_id: @project.identifier, issue_id: issue.id, source: @next.id }
    assert_response :success
    assert_equal @next.id, issue.reload.fixed_version_id
  end

  def test_pull_rejects_qa_sp_without_be_or_fe
    post :pull, params: { project_id: @project.identifier, issue_id: @backlog_issue.id, version_id: @sprint.id,
                          status_id: 1, sp: { qa: '2' } }
    assert_response :unprocessable_entity
    assert_nil @backlog_issue.reload.fixed_version_id

    post :pull, params: { project_id: @project.identifier, issue_id: @backlog_issue.id, version_id: @sprint.id,
                          status_id: 1, sp: { be: '1', qa: '2' } }
    assert_response :success
    assert_equal '2', @backlog_issue.reload.custom_field_value(@qa)
  end

  def test_panel_is_off_unless_enabled_in_settings
    enable_roadmap!(@project, 'backlog_enabled' => '1', 'agile_board_backlog_enabled' => '0')
    get :index, params: { project_id: @project.identifier }
    assert_response :not_found
    post :pull, params: { project_id: @project.identifier, issue_id: @backlog_issue.id, version_id: @sprint.id,
                          status_id: 1 }
    assert_response :not_found
    assert_equal '0', SananAgile::ProjectSettings::DEFAULTS['agile_board_backlog_enabled']
  end

  def test_index_shows_sp_done_parts_and_subtask_progress
    sp = IssueCustomField.create!(name: 'SP total', field_format: 'float', is_for_all: true, tracker_ids: [1])
    done_be = IssueCustomField.create!(name: 'Done BE in sprint', field_format: 'version', is_for_all: true,
                                       tracker_ids: [1])
    enable_roadmap!(@project, 'backlog_enabled' => '1', 'agile_board_backlog_enabled' => '1',
                              'standard_tracker' => ['1'], 'story_point_cfid' => sp.id.to_s,
                              'done_be_cfid' => done_be.id.to_s)
    @project.reload
    old = Version.create!(project: @project, name: 'Old sprint', status: 'open')
    story = Issue.create!(project: @project, tracker_id: 1, author_id: 2, subject: 'With extras', status_id: 1,
                          priority: IssuePriority.first,
                          custom_field_values: { sp.id.to_s => '5', done_be.id.to_s => old.id.to_s })
    Issue.create!(project: @project, tracker_id: 2, author_id: 2, subject: 'Child open', status_id: 1,
                  priority: IssuePriority.first, parent_issue_id: story.id)
    Issue.create!(project: @project, tracker_id: 2, author_id: 2, subject: 'Child closed', status_id: 1,
                  priority: IssuePriority.first, parent_issue_id: story.id).update_column(:status_id, 5)

    get :index, params: { project_id: @project.identifier, q: 'With extras' }
    item = json['issues'].find { |i| i['id'] == story.id }
    assert_equal 5, item['sp']
    assert_equal 'Old sprint', item['done_be']
    assert_nil item['done_fe']
    assert_equal({ 'done' => 1, 'total' => 2 }, item['subtasks'])
  end

  def test_index_gives_size_and_sprint_team_sp_of_a_sprint_ticket
    SananIssueSpSize.create!(issue_id: @next_issue.id, sp_be: 3, sp_qa: 1)
    @next_issue.reload.custom_field_values = { @be.id.to_s => '2' }
    @next_issue.save!
    get :index, params: { project_id: @project.identifier, source: @next.id, target_version_id: @sprint.id }
    item = json['issues'].find { |i| i['id'] == @next_issue.id }
    assert_equal({ 'be' => 3, 'qa' => 1 }, item['size'])
    assert_equal({ 'be' => 2 }, item['sprint_sp'])
  end
end
