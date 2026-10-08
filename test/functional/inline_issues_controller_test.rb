# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class InlineIssuesControllerTest < Redmine::ControllerTest
  include SananRoadmapTestHelper
  tests SananAgile::InlineIssuesController
  fixtures(*ROADMAP_FIXTURES)

  def setup
    @project = Project.find(1)
    enable_roadmap!(@project, 'issues_inline_edit_enabled' => '1')
    @issue = Issue.create!(project: @project, tracker_id: 1, author_id: 2, subject: 'Inline', status_id: 1,
                           priority: IssuePriority.first).reload # creation bumps lock_version (nested set)
    @request.session[:user_id] = 2
  end

  def json
    JSON.parse(response.body)
  end

  def test_editor_lists_the_statuses_the_workflow_allows
    get :show, params: { id: @issue.id, field: 'status' }
    assert_response :success
    assert_equal 'select', json['type']
    assert_equal '1', json['value']
    allowed = @issue.new_statuses_allowed_to(User.find(2)).map { |s| s.id.to_s }
    assert_equal allowed, json['options'].map(&:last)
  end

  def test_update_saves_the_value_and_journals_it
    patch :update, params: { id: @issue.id, field: 'due_date', value: '2026-12-31',
                             lock_version: @issue.lock_version }
    assert_response :success
    assert json['html'].include?('12/31/2026') || json['html'].include?('2026-12-31')
    assert_equal Date.new(2026, 12, 31), @issue.reload.due_date
    assert @issue.journals.last.details.any? { |d| d.prop_key == 'due_date' }
  end

  def test_status_the_workflow_does_not_allow_is_refused
    WorkflowTransition.where(tracker_id: 1, old_status_id: 1, new_status_id: 4).delete_all
    patch :update, params: { id: @issue.id, field: 'status', value: '4', lock_version: @issue.lock_version }
    assert_response :unprocessable_entity
    assert_equal 1, @issue.reload.status_id
  end

  def test_custom_field_cell
    cf = IssueCustomField.create!(name: 'Inline CF', field_format: 'string', is_for_all: true, tracker_ids: [1])
    @project.reload
    patch :update, params: { id: @issue.id, field: "cf_#{cf.id}", value: 'hello', lock_version: @issue.lock_version }
    assert_response :success
    assert_equal 'hello', @issue.reload.custom_field_value(cf)
  end

  def test_stale_lock_version_is_a_conflict
    patch :update, params: { id: @issue.id, field: 'subject', value: 'New', lock_version: @issue.lock_version - 1 }
    assert_response :conflict
    assert_equal 'Inline', @issue.reload.subject
  end

  def test_user_without_edit_permission_cannot_edit
    Role.find(1).remove_permission!(:edit_issues)
    Role.find(1).remove_permission!(:edit_own_issues)
    get :show, params: { id: @issue.id, field: 'status' }
    assert_response :forbidden
  end

  def test_disabled_in_settings
    enable_roadmap!(@project, 'issues_inline_edit_enabled' => '0')
    get :show, params: { id: @issue.id, field: 'status' }
    assert_response :not_found
  end

  def test_story_point_fields_are_picked_on_the_fibonacci_scale
    be = IssueCustomField.create!(name: 'SP BE', field_format: 'float', is_for_all: true, tracker_ids: [1])
    total = IssueCustomField.create!(name: 'SP total', field_format: 'int', is_for_all: true, tracker_ids: [1])
    enable_roadmap!(@project, 'issues_inline_edit_enabled' => '1', 'sp_be_cfid' => be.id.to_s,
                              'story_point_cfid' => total.id.to_s)
    @project.reload

    get :show, params: { id: @issue.id, field: "cf_#{be.id}" }
    assert_equal 'select', json['type']
    assert_equal %w[0 0.5 1 2 3 5 8 13 20 40 100], json['options'].map(&:last)

    get :show, params: { id: @issue.id, field: "cf_#{total.id}" }
    assert_not_includes json['options'].map(&:last), '0.5' # integer field

    patch :update, params: { id: @issue.id, field: "cf_#{be.id}", value: '5', lock_version: @issue.reload.lock_version }
    assert_response :success
    assert_equal 5.0, @issue.reload.custom_field_value(be).to_f
  end

  def test_editing_a_part_returns_the_re_derived_total_cell
    be, qa, total = %w[BE QA Total].map do |n|
      IssueCustomField.create!(name: "Inline SP #{n}", field_format: 'float', is_for_all: true, tracker_ids: [1])
    end
    enable_roadmap!(@project, 'issues_inline_edit_enabled' => '1', 'sp_be_cfid' => be.id.to_s, 'sp_qa_cfid' => qa.id.to_s,
                              'sp_sprint_total_cfid' => total.id.to_s, 'sp_total_formula' => 'max', 'sp_total_require_qa' => '0')
    @project.reload
    patch :update, params: { id: @issue.id, field: "cf_#{be.id}", value: '3', lock_version: @issue.reload.lock_version }
    assert_response :success
    assert_equal '3', @issue.reload.custom_field_value(total).to_s.sub(/\.0\z/, '')
    assert_match(/3/, json['cells']["cf_#{total.id}"])
  end

  def test_integer_sp_fields_become_decimal_for_half_points
    require File.expand_path('../../db/migrate/20261005140000_story_point_fields_allow_half_points', __dir__)
    sp = IssueCustomField.create!(name: 'Int SP', field_format: 'int', is_for_all: true, tracker_ids: [1])
    other = IssueCustomField.create!(name: 'Int other', field_format: 'int', is_for_all: true, tracker_ids: [1])
    Setting.plugin_sanan_redmine_agile = { '1' => { 'sp_be_cfid' => sp.id.to_s } }
    ActiveRecord::Migration.suppress_messages { StoryPointFieldsAllowHalfPoints.new.up }
    assert_equal 'float', sp.reload.field_format
    assert_equal 'int', other.reload.field_format # not an SP field
  end
end
