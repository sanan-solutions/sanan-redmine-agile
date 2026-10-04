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

  def test_report_shows_part_percentages_and_dod_sp
    get :show, params: { project_id: @project.identifier, id: @sprint.id }
    assert_response :success
    assert_select '.sr-kpi__pct', text: /100%/            # BE: 4 done / 4 committed
    assert_select '.sr-kpi--total .sr-kpi__label', text: I18n.t(:label_sprint_report_dod_sp)
    assert_select '#sr-commit-tickets h3', text: /\(1\)/   # the BE-only ticket is committed
  end
end
