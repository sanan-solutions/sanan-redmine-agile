# frozen_string_literal: true
class SananAgile::ProjectSettingsController < ApplicationController
  before_action :find_project
  before_action :authorize # dựa theo permission :manage_sanan_agile_settings

  def update
    cfg = params.require(:settings)
                .permit(:sanan_agile_enabled,
                  :sanan_agile_version_strategy, 
                  :skip_if_already_set, 

                  :code_done_status_name,
                  :code_done_cfid,

                  :development_done_status_name,
                  :development_done_cfid, 
                  
                  :uat_done_status_name, 
                  :uat_done_cfid,

                  { dod_checkbox_trackers: [] },
                  { dod_checkbox_statuses: [] },
                  :dod_cfid,
                  :story_point_cfid,

                  :sp_be_cfid, :sp_fe_cfid, :done_be_cfid, :done_fe_cfid,
                  :auto_move_enabled, :auto_move_status_id,:resolve_status,
                  befe_trackers: [],
                  befe_statuses: [],
                  
                )
    SananAgile::ProjectSettings.save(@project.id, cfg)
    flash[:notice] = l(:notice_successful_update)
    redirect_to settings_project_path(@project) # quay lại trang Settings (giữ dải tabs)
  end

  private

  def find_project
    @project = Project.find(params[:project_id])
  end
end
