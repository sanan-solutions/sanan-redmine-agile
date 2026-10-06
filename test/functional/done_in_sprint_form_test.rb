# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# Done in sprint fields are filled on save whatever the screen (issue form, global modal, board, inline edit).
class DoneInSprintFormTest < Redmine::ControllerTest
  include SananRoadmapTestHelper
  tests IssuesController
  fixtures(*ROADMAP_FIXTURES)

  def test_status_change_from_the_issue_form_fills_the_done_field
    project = Project.find(1)
    done_qa = IssueCustomField.create!(name: 'Done QA In Sprint', field_format: 'version', is_for_all: true, tracker_ids: [1])
    sprint = Version.create!(project: project, name: 'Sprint form', status: 'open')
    enable_roadmap!(project, 'done_qa_cfid' => done_qa.id.to_s, 'done_qa_status_name' => IssueStatus.find(3).name)
    project.reload
    issue = Issue.create!(project: project, tracker_id: 1, author_id: 2, subject: 'Form', status_id: 1,
                          fixed_version: sprint, priority: IssuePriority.first)
    @request.session[:user_id] = 2

    put :update, params: { id: issue.id, issue: { status_id: '3' } }, xhr: true # the modal posts the same form
    assert_includes [200, 302], response.status
    assert_equal sprint.id.to_s, issue.reload.custom_field_value(done_qa)
  end
end
