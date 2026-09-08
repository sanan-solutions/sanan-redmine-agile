# frozen_string_literal: true

# JSON map of issue_id → intake source for Agile board badges/filter.
class IntakeBadgesController < ApplicationController
  before_action :find_project
  before_action :require_login
  accept_api_auth :source_map

  # [{ issue_id: 123, source: "cs"|"sale"|"product" }, ...]
  def source_map
    cfg = SananAgile::ProjectSettings.load(@project.id)
    cfid = SananAgile::IntakeSource.cfid(cfg)
    if cfid <= 0 || (cfg['cs_backlog_enabled'].to_s != '1' && cfg['sale_backlog_enabled'].to_s != '1')
      return render json: []
    end

    rows = CustomValue.where(
      customized_type: 'Issue',
      custom_field_id: cfid
    ).joins('INNER JOIN issues ON issues.id = custom_values.customized_id')
     .where(issues: { project_id: @project.id })
     .pluck('issues.id', 'custom_values.value')

    out = rows.map do |issue_id, value|
      src = SananAgile::IntakeSource.normalize(value)
      next unless %w[cs sale].include?(src)

      { issue_id: issue_id, source: src }
    end.compact

    render json: out
  end

  private

  def find_project
    @project = Project.find(params[:project_id])
  end
end
