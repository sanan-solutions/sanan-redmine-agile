# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# Sub-tasks carry only a personal SP; team SP (BE/FE/QA) + derived Total are for standard tickets.
class IssueSpSubtaskTest < Redmine::ControllerTest
  include SananRoadmapTestHelper
  tests IssuesController
  fixtures(*ROADMAP_FIXTURES)

  SUBTASK_TRACKER_ID = 3 # "Support request" in fixtures, configured as sub-task tracker
  STANDARD_TRACKER_ID = 1

  def setup
    @project = Project.find(1)
    @cfs = %w[SP BE FE QA].to_h do |n|
      [n, IssueCustomField.create!(name: "SP #{n}", field_format: 'float', is_for_all: true,
                                   tracker_ids: [1, 2, 3])]
    end
    enable_roadmap!(@project,
                    'story_point_cfid' => @cfs['SP'].id.to_s, 'sp_be_cfid' => @cfs['BE'].id.to_s,
                    'sp_fe_cfid' => @cfs['FE'].id.to_s, 'sp_qa_cfid' => @cfs['QA'].id.to_s,
                    'sp_total_formula' => 'max', 'sp_total_require_qa' => '1',
                    'standard_tracker' => [STANDARD_TRACKER_ID.to_s], 'subtask_tracker' => [SUBTASK_TRACKER_ID.to_s],
                    'epic_tracker' => '') # tracker 2 is a plain non-standard tracker here
    @request.session[:user_id] = 2
  end

  def create_issue(tracker_id)
    Issue.create!(project: @project, tracker_id: tracker_id, author_id: 2, subject: 'SP test',
                  status_id: 1, priority: IssuePriority.default || IssuePriority.first)
  end

  def sp_of(issue)
    issue.reload.custom_field_value(@cfs['SP']).to_s
  end

  def test_subtask_keeps_personal_sp_without_team_sp
    issue = create_issue(SUBTASK_TRACKER_ID)
    put :update, params: { id: issue.id, issue: { custom_field_values: { @cfs['SP'].id.to_s => '3' } } }
    assert_response :redirect
    assert_equal '3', sp_of(issue)
  end

  def test_subtask_ignores_team_size_params
    issue = create_issue(SUBTASK_TRACKER_ID)
    put :update, params: { id: issue.id, issue: { custom_field_values: { @cfs['SP'].id.to_s => '2' } },
                           sanan_sp_size: { sp_be: '5', sp_fe: '8' } }
    assert_equal '2', sp_of(issue)
    assert_nil SananIssueSpSize.find_by(issue_id: issue.id)
  end

  def test_standard_ticket_still_derives_total
    issue = create_issue(STANDARD_TRACKER_ID)
    # require QA: no QA size → Total cleared, as before for standard tickets
    put :update, params: { id: issue.id, issue: { custom_field_values: { @cfs['SP'].id.to_s => '3' } },
                           sanan_sp_size: { sp_be: '5', sp_fe: '2' } }
    assert_equal '', sp_of(issue)
    put :update, params: { id: issue.id, sanan_sp_size: { sp_be: '5', sp_fe: '2', sp_qa: '3' },
                           issue: { custom_field_values: { @cfs['SP'].id.to_s => '' } } }
    assert_equal '5', sp_of(issue) # max(BE, FE, QA)
  end

  def test_subtask_form_shows_personal_sp_only
    issue = create_issue(SUBTASK_TRACKER_ID)
    get :edit, params: { id: issue.id }
    assert_response :success
    assert_select '#sanan-sp-personal-form'
    assert_select '#sanan-sp-size-form', 0
    assert_select '#sanan-sp-sprint-form', 0
  end

  def test_non_standard_tracker_without_subtask_setting_is_personal
    # tracker 2 is neither standard nor listed as sub-task tracker
    issue = create_issue(2)
    put :update, params: { id: issue.id, issue: { custom_field_values: { @cfs['SP'].id.to_s => '3' } } }
    assert_equal '3', sp_of(issue)
    get :edit, params: { id: issue.id }
    assert_select '#sanan-sp-personal-form'
    assert_select '#sanan-sp-size-form', 0
  end

  def test_epic_tracker_keeps_team_sizes
    enable_roadmap!(@project, SananAgile::ProjectSettings.load(@project.id).merge('epic_tracker' => '2'))
    issue = create_issue(2)
    get :edit, params: { id: issue.id }
    assert_select '#sanan-sp-size-form'
    assert_select '#sanan-sp-personal-form', 0
  end

  def test_standard_form_keeps_team_sizes
    issue = create_issue(STANDARD_TRACKER_ID)
    get :edit, params: { id: issue.id }
    assert_select '#sanan-sp-size-form'
    assert_select '#sanan-sp-personal-form', 0
  end
end
