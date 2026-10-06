# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# Story points live in issue custom fields (SananAgile::IssueSp): Size BE / FE / QA / Total and This-sprint
# BE / FE / QA / Total. Sub-tasks carry only the sprint Total, as their personal SP.
class IssueSpSubtaskTest < Redmine::ControllerTest
  include SananRoadmapTestHelper
  tests IssuesController
  fixtures(*ROADMAP_FIXTURES)

  SUBTASK_TRACKER_ID = 3 # "Support request" in fixtures, configured as sub-task tracker
  STANDARD_TRACKER_ID = 1
  KEYS = {
    'SIZE' => 'story_point_cfid', 'SBE' => 'size_be_cfid', 'SFE' => 'size_fe_cfid', 'SQA' => 'size_qa_cfid',
    'BE' => 'sp_be_cfid', 'FE' => 'sp_fe_cfid', 'QA' => 'sp_qa_cfid', 'TOTAL' => 'sp_sprint_total_cfid'
  }.freeze

  def setup
    @project = Project.find(1)
    @cfs = KEYS.keys.to_h do |n|
      [n, IssueCustomField.create!(name: "SP #{n}", field_format: 'float', is_for_all: true, tracker_ids: [1, 2, 3])]
    end
    enable_roadmap!(@project, KEYS.to_h { |n, key| [key, @cfs[n].id.to_s] }.merge(
      'sp_total_formula' => 'max', 'sp_total_require_qa' => '1',
      'standard_tracker' => [STANDARD_TRACKER_ID.to_s], 'subtask_tracker' => [SUBTASK_TRACKER_ID.to_s],
      'epic_tracker' => '')) # tracker 2 is a plain non-standard tracker here
    @project.reload
    @sprint = Version.create!(project: @project, name: 'Sprint SP', status: 'open')
    @request.session[:user_id] = 2
  end

  def create_issue(tracker_id, version: nil)
    Issue.create!(project: @project, tracker_id: tracker_id, author_id: 2, subject: 'SP test', status_id: 1,
                  fixed_version: version, priority: IssuePriority.default || IssuePriority.first).reload
  end

  def val(issue, name)
    issue.reload.custom_field_value(@cfs[name]).to_s
  end

  def cfv(values)
    values.to_h { |name, v| [@cfs[name].id.to_s, v] }
  end

  def test_subtask_personal_sp_is_the_sprint_total
    issue = create_issue(SUBTASK_TRACKER_ID)
    put :update, params: { id: issue.id, issue: { custom_field_values: cfv('TOTAL' => '3') } }
    assert_response :redirect
    assert_equal '3', val(issue, 'TOTAL')
  end

  def test_size_and_sprint_totals_follow_the_formula
    issue = create_issue(STANDARD_TRACKER_ID)
    # require QA: no QA → Totals stay empty
    put :update, params: { id: issue.id, issue: { custom_field_values: cfv('SBE' => '5', 'SFE' => '2', 'BE' => '2') } }
    assert_equal '', val(issue, 'SIZE')
    assert_equal '', val(issue, 'TOTAL')
    put :update, params: { id: issue.id, issue: { custom_field_values: cfv('SQA' => '3', 'QA' => '1') } }
    assert_equal '5', val(issue, 'SIZE')  # max(5, 2, 3)
    assert_equal '2', val(issue, 'TOTAL') # max(2, 1)
  end

  def test_total_set_by_hand_is_kept_when_parts_change
    issue = create_issue(STANDARD_TRACKER_ID)
    put :update, params: { id: issue.id, issue: { custom_field_values: cfv('BE' => '2', 'QA' => '1') } }
    assert_equal '2', val(issue, 'TOTAL')
    put :update, params: { id: issue.id, issue: { custom_field_values: cfv('TOTAL' => '8') } } # by hand
    put :update, params: { id: issue.id, issue: { custom_field_values: cfv('BE' => '3') } }
    assert_equal '8', val(issue, 'TOTAL')
  end

  def test_total_following_the_formula_is_recomputed
    issue = create_issue(STANDARD_TRACKER_ID)
    put :update, params: { id: issue.id, issue: { custom_field_values: cfv('BE' => '2', 'QA' => '1') } }
    put :update, params: { id: issue.id, issue: { custom_field_values: cfv('BE' => '5') } }
    assert_equal '5', val(issue, 'TOTAL')
  end

  def test_leaving_a_sprint_keeps_its_sp_in_the_history_and_clears_the_fields
    issue = create_issue(STANDARD_TRACKER_ID, version: @sprint)
    put :update, params: { id: issue.id, issue: { custom_field_values: cfv('BE' => '2', 'QA' => '1', 'TOTAL' => '3') } }
    put :update, params: { id: issue.id, issue: { fixed_version_id: '' } }
    row = SananIssueSprintSp.find_by(issue_id: issue.id, version_id: @sprint.id)
    assert_equal [2.0, 1.0, 3.0], [row.sp_be.to_f, row.sp_qa.to_f, row.sp_total.to_f]
    assert_equal ['', '', ''], [val(issue, 'BE'), val(issue, 'QA'), val(issue, 'TOTAL')]
  end

  def test_entering_a_sprint_from_the_backlog_keeps_the_re_estimate
    issue = create_issue(STANDARD_TRACKER_ID)
    put :update, params: { id: issue.id, issue: { custom_field_values: cfv('BE' => '3', 'QA' => '1') } }
    put :update, params: { id: issue.id, issue: { fixed_version_id: @sprint.id.to_s } }
    assert_equal '3', val(issue, 'BE')
    assert_equal '3', val(issue, 'TOTAL')
    assert_nil SananIssueSprintSp.find_by(issue_id: issue.id)
  end

  def test_subtask_form_shows_personal_sp_only
    issue = create_issue(SUBTASK_TRACKER_ID)
    get :edit, params: { id: issue.id }
    assert_response :success
    assert_select '#sanan-sp-personal-form'
    assert_select "#sanan-sp-personal-form select[name='issue[custom_field_values][#{@cfs['TOTAL'].id}]']"
    assert_select '#sanan-sp-size-form', 0
    assert_select '#sanan-sp-sprint-form', 0
  end

  def test_non_standard_tracker_without_subtask_setting_is_personal
    issue = create_issue(2) # neither standard nor listed as sub-task tracker
    get :edit, params: { id: issue.id }
    assert_select '#sanan-sp-personal-form'
    assert_select '#sanan-sp-size-form', 0
  end

  def test_standard_form_has_size_and_sprint_groups_even_in_the_backlog
    issue = create_issue(STANDARD_TRACKER_ID)
    get :edit, params: { id: issue.id }
    assert_select '#sanan-sp-size-form'
    assert_select '#sanan-sp-sprint-form:not([hidden])'
    assert_select '#sanan-sp-personal-form', 0
  end

  def test_a_total_typed_by_hand_is_kept_even_while_qa_is_missing
    issue = create_issue(STANDARD_TRACKER_ID)
    put :update, params: { id: issue.id, issue: { custom_field_values: cfv('SIZE' => '8', 'SBE' => '5') } }
    assert_equal '8', val(issue, 'SIZE') # require QA only keeps a *derived* Total empty
  end
end
