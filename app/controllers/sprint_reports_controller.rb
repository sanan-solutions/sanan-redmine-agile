# frozen_string_literal: true
require_dependency File.expand_path('../../lib/sanan_agile/sprint_report/calculator', __dir__)
require_dependency File.expand_path('../../lib/sanan_agile/sprint_report/history', __dir__)

class SprintReportsController < ApplicationController
  unloadable
  before_action :find_project_by_project_id
  before_action :find_version
  before_action :ensure_sanan_agile_enabled
  before_action :authorize

  helper :sprint_reports

  def show
    @cfg = SananAgile::ProjectSettings.load(@project.id)
    @settings = @cfg
    @report = SananAgile::SprintReport::Calculator.call(@version, cfg: @cfg)
    @history = SananAgile::SprintReport::History.call(@version, cfg: @cfg)
  end

  private

  def find_version
    @version = @project.shared_versions.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def ensure_sanan_agile_enabled
    cfg = SananAgile::ProjectSettings.load(@project.id)
    return if cfg['sanan_agile_enabled'].to_s == '1'

    render_404
  end
end
