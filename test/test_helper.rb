# frozen_string_literal: true

require File.expand_path('../../../test/test_helper', __dir__)

module SananRoadmapTestHelper
  ROADMAP_FIXTURES = %i[projects users email_addresses roles members member_roles issues issue_statuses
                        trackers projects_trackers enabled_modules enumerations workflows versions
                        custom_fields custom_values custom_fields_projects custom_fields_trackers
                        journals journal_details issue_categories].freeze

  EPIC_TRACKER_ID = 2 # "Feature request" in Redmine fixtures
  STORY_TRACKER_ID = 1 # "Bug"

  # Enables the plugin module + roadmap on a project and grants the roadmap permissions to Manager (role 1).
  def enable_roadmap!(project = Project.find(1), extra = {})
    project.enable_module!(:sanan_agile)
    store = Setting.plugin_sanan_redmine_agile || {}
    store[project.id.to_s] = SananAgile::ProjectSettings::DEFAULTS.merge(
      'sanan_agile_enabled' => '1', 'roadmap_enabled' => '1', 'epic_tracker' => EPIC_TRACKER_ID.to_s
    ).merge(extra)
    Setting.plugin_sanan_redmine_agile = store
    Role.find(1).add_permission!(:view_roadmap, :manage_roadmap)
    project
  end

  def roadmap_cfg(project = Project.find(1))
    SananAgile::ProjectSettings.load(project.id)
  end

  def create_epic!(project = Project.find(1), subject: 'Epic')
    Issue.create!(project: project, tracker_id: EPIC_TRACKER_ID, author_id: 2, subject: subject,
                  status_id: 1, priority: IssuePriority.default || IssuePriority.first)
  end

  def create_story!(epic, closed: false, subject: 'Story')
    Issue.create!(project: epic.project, tracker_id: STORY_TRACKER_ID, author_id: 2, subject: subject,
                  parent_issue_id: epic.id, status_id: closed ? 5 : 1,
                  priority: IssuePriority.default || IssuePriority.first)
  end

  def plan!(epic, year, quarter, health: 'on_track')
    SananRoadmapItem.create!(project_id: epic.project_id, issue_id: epic.id, year: year, quarter: quarter,
                             position: 0, health: health)
  end
end
