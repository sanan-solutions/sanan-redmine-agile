# frozen_string_literal: true

# JSON map of epics and issue→epic for Agile board filter.
class EpicBadgesController < ApplicationController
  before_action :find_project
  before_action :require_login
  accept_api_auth :epic_map

  # { epics: [{id, name}], issues: [{issue_id, epic_id}] }
  def epic_map
    cfg = SananAgile::ProjectSettings.load(@project.id)
    epic_tracker = cfg['epic_tracker'].to_i
    if epic_tracker <= 0
      return render json: { epics: [], issues: [] }
    end

    epics = Issue.visible.where(project_id: @project.id, tracker_id: epic_tracker)
                 .order(:id)
                 .pluck(:id, :subject)
    epic_ids = epics.map(&:first)
    if epic_ids.empty?
      return render json: { epics: [], issues: [] }
    end

    children = Issue.where(project_id: @project.id, parent_id: epic_ids)
                    .pluck(:id, :parent_id)
    story_to_epic = children.to_h
    issues = children.map { |id, pid| { issue_id: id, epic_id: pid } }

    if story_to_epic.any?
      Issue.where(project_id: @project.id, parent_id: story_to_epic.keys).pluck(:id, :parent_id).each do |id, parent_id|
        epic_id = story_to_epic[parent_id]
        next unless epic_id

        issues << { issue_id: id, epic_id: epic_id }
      end
    end

    render json: {
      epics: epics.map { |id, name| { id: id, name: name } },
      issues: issues
    }
  end

  private

  def find_project
    @project = Project.find(params[:project_id])
  end
end
