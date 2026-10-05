# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class DoneInSprintTest < ActiveSupport::TestCase
  include SananRoadmapTestHelper
  fixtures(*ROADMAP_FIXTURES)

  RESOLVED = 3 # "Resolved" in Redmine fixtures

  def setup
    @project = Project.find(1)
    @done_qa = IssueCustomField.create!(name: 'Done QA In Sprint', field_format: 'version', is_for_all: true,
                                        tracker_ids: [1])
    @sprint = Version.create!(project: @project, name: 'Sprint QA', status: 'open')
    @other = Version.create!(project: @project, name: 'Default sprint', status: 'open')
    @project.update_column(:default_version_id, @other.id)
    @backlog = Version.create!(project: @project, name: 'Product Backlog', status: 'open')
    enable_roadmap!(@project, 'done_qa_cfid' => @done_qa.id.to_s,
                              'done_qa_status_name' => IssueStatus.find(RESOLVED).name,
                              'backlog_version_id' => @backlog.id.to_s)
    @project.reload
    User.current = User.find(2)
  end

  def new_issue(attrs = {})
    Issue.new({ project: @project, tracker_id: 1, author_id: 2, subject: 'QA', status_id: 1,
                priority: IssuePriority.first, fixed_version: @sprint }.merge(attrs))
  end

  def test_created_directly_in_trigger_status_stamps_its_own_sprint_in_one_save
    issue = new_issue(status_id: RESOLVED)
    assert issue.save, issue.errors.full_messages.join(', ')
    assert_equal @sprint.id.to_s, issue.reload.custom_field_value(@done_qa.id)
  end

  def test_status_change_stamps_its_own_sprint_and_journals_it
    issue = new_issue
    issue.save!
    issue = Issue.find(issue.id)
    issue.init_journal(User.find(2))
    issue.status_id = RESOLVED
    issue.save!

    assert_equal @sprint.id.to_s, issue.reload.custom_field_value(@done_qa.id)
    assert issue.journals.last.details.any? { |d| d.prop_key == @done_qa.id.to_s && d.value == @sprint.id.to_s }
  end

  def test_ticket_not_on_a_sprint_uses_the_default_version
    issue = new_issue(status_id: RESOLVED, fixed_version: @backlog)
    issue.save!
    assert_equal @other.id.to_s, issue.reload.custom_field_value(@done_qa.id)
  end

  def test_other_statuses_do_not_stamp
    issue = new_issue(status_id: 2)
    issue.save!
    assert_nil issue.reload.custom_field_value(@done_qa.id).presence
  end

  def test_legacy_development_done_settings_become_done_qa
    legacy = IssueCustomField.create!(name: 'Dev done', field_format: 'version', is_for_all: true)
    enable_roadmap!(@project, 'done_qa_cfid' => '', 'done_qa_status_name' => '',
                              'development_done_cfid' => legacy.id.to_s,
                              'development_done_status_name' => 'Resolved')
    cfg = SananAgile::ProjectSettings.load(@project.id)
    assert_equal legacy.id.to_s, cfg['done_qa_cfid']
    assert_equal 'Resolved', cfg['done_qa_status_name']
    assert_not cfg.key?('development_done_cfid')
  end
end
