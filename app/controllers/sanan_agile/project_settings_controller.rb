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

                  :sp_be_cfid, :sp_fe_cfid, :done_be_cfid, :done_fe_cfid, :done_qa_cfid,
                  :auto_move_enabled, :auto_move_status_id,:resolve_status,
                  :sp_qa_cfid,
                  :sp_actual_version_cfid,
                  :sp_be_actual_version_cfid,
                  :sp_fe_actual_version_cfid,
                  :sp_qa_actual_version_cfid,
                  :sp_commit_version_cfid,
                  :sp_be_commit_version_cfid,
                  :sp_fe_commit_version_cfid,
                  :sp_qa_commit_version_cfid,
                  :card_color_tracker_mode,
                  :test_level_cfid,
                  { card_color_tracker_map: {} },
                 
                  {befe_trackers: []},
                  {befe_statuses: []},   
                  {release_status_filter_ids: []},
                  :epic_tracker,
                  {standard_tracker: []},
                  {subtask_tracker: []},
                  :release_add_child_issue_standard_tracker,
                  :release_released_status_id,
                  :release_close_status_id,
                  :backlog_enabled,
                  {backlog_trackers: []},
                  :backlog_hide_subtasks,
                  :cs_backlog_enabled,
                  :sale_backlog_enabled,
                  :cs_queue_version_id,
                  :sale_queue_version_id,
                  :intake_source_cfid,
                  {cs_ready_status_ids: []},
                  {sale_ready_status_ids: []},
                  :default_cs_quota_sp,
                  :default_sale_quota_sp,
                  :allow_quota_override,
                  :intake_ready_sla_days,
                  :cs_ready_sp_alert_threshold,
                  :sale_ready_sp_alert_threshold,
                  :intake_ready_sp_alert_mail,
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
