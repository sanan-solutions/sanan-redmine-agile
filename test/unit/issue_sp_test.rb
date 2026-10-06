# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class IssueSpTest < ActiveSupport::TestCase
  include SananRoadmapTestHelper
  fixtures(*ROADMAP_FIXTURES)

  def setup
    User.current = User.find(1)
    @project = Project.find(1)
    @size, @sbe, @total, @be = %w[Size SizeBE Total BE].map do |n|
      IssueCustomField.create!(name: "IssueSp #{n}", field_format: 'float', is_for_all: true, tracker_ids: [1, 3])
    end
    enable_roadmap!(@project, 'story_point_cfid' => @size.id.to_s, 'size_be_cfid' => @sbe.id.to_s,
                              'sp_sprint_total_cfid' => @total.id.to_s, 'sp_be_cfid' => @be.id.to_s,
                              'standard_tracker' => ['1'], 'subtask_tracker' => ['3'], 'epic_tracker' => '')
    @project.reload
    @sprint = Version.create!(project: @project, name: 'Sprint P', status: 'open')
  end

  def cfg
    SananAgile::ProjectSettings.load(@project.id)
  end

  def issue(values = {}, version: nil)
    Issue.create!(project: @project, tracker_id: 1, author_id: 2, subject: 'P', status_id: 1, fixed_version: version,
                  priority: IssuePriority.first, custom_field_values: values.transform_keys { |cf| cf.id.to_s })
  end

  def test_planning_sp_is_the_sprint_estimate_else_the_size_of_a_never_planned_ticket
    planned = issue({ @size => '5', @total => '3' })
    fresh = issue({ @size => '8' })
    back = issue({ @size => '5', @be => '2' }, version: @sprint).reload
    back.fixed_version = nil
    back.save! # leaves the sprint: snapshot, fields cleared

    plan = SananAgile::IssueSp.planning_sp([planned.id, fresh.id, back.id], cfg)
    assert_equal 3, plan[planned.id]   # re-estimated
    assert_equal 8, plan[fresh.id]     # never planned: its Size
    assert_nil plan[back.id]           # back from a sprint without a new estimate
    assert SananIssueSprintSp.exists?(issue_id: back.id, version_id: @sprint.id)
  end

  def test_migration_moves_sizes_current_sprint_totals_and_personal_sp
    require File.expand_path('../../db/migrate/20261005120000_story_points_in_custom_fields', __dir__)
    enable_roadmap!(@project, 'story_point_cfid' => @size.id.to_s, 'sp_be_cfid' => @be.id.to_s,
                              'standard_tracker' => ['1'], 'subtask_tracker' => ['3'], 'epic_tracker' => '')
    sized = issue
    ActiveRecord::Base.connection.execute(
      "INSERT INTO sanan_issue_sp_sizes (issue_id, sp_be, sp_fe, sp_qa, created_at, updated_at) VALUES (#{sized.id}, 3, 2, NULL, '2026-01-01', '2026-01-01')"
    )
    on_sprint = issue({}, version: @sprint)
    SananIssueSprintSp.create!(issue_id: on_sprint.id, version_id: @sprint.id, sp_total: 5, captured_at: Time.current)
    sub = Issue.create!(project: @project, tracker_id: 3, author_id: 2, subject: 'Sub', status_id: 1,
                        priority: IssuePriority.first, custom_field_values: { @size.id.to_s => '2' })

    ActiveRecord::Migration.suppress_messages { StoryPointsInCustomFields.new.up }

    c = SananAgile::ProjectSettings.load(@project.id)
    %w[size_be_cfid size_fe_cfid size_qa_cfid sp_sprint_total_cfid].each { |k| assert c[k].to_i.positive?, k }
    assert_equal 3, SananAgile::IssueSp.values(sized.reload, c, :size).sp_be
    assert_equal 2, SananAgile::IssueSp.values(sized, c, :size).sp_fe
    assert_equal 5, SananAgile::IssueSp.values(on_sprint.reload, c, :sprint).sp_total
    assert_not SananIssueSprintSp.exists?(issue_id: on_sprint.id) # history keeps only left sprints
    assert_equal 2, SananAgile::IssueSp.values(sub.reload, c, :sprint).sp_total
    assert_equal '', sub.custom_field_value(@size).to_s
  end

  def test_field_names_follow_one_pattern
    require File.expand_path('../../db/migrate/20261005130000_standard_story_point_field_names', __dir__)
    taken = IssueCustomField.create!(name: 'Sprint SP - Backend', field_format: 'string', is_for_all: true)
    Setting.plugin_sanan_redmine_agile = { '1' => Setting.plugin_sanan_redmine_agile['1'] } # this project only
    ActiveRecord::Migration.suppress_messages { StandardStoryPointFieldNames.new.up }
    assert_equal 'Size - Total', @size.reload.name
    assert_equal 'Size - Backend', @sbe.reload.name
    assert_equal 'Sprint SP - Total', @total.reload.name
    assert_equal 'IssueSp BE', @be.reload.name # name already used by another field: left as is
    assert_equal 'Sprint SP - Backend', taken.reload.name
  end
end
