# frozen_string_literal: true

# Plugin-wide settings (Administration → Sanan Agile): the defaults every project follows unless it sets its own.
class SananAgile::GlobalSettingsController < ApplicationController
  layout 'admin'
  self.main_menu = false
  before_action :require_admin

  def edit; end

  def update
    SananAgile::ProjectSettings.save_global(SananAgile::ProjectSettingsController.permitted(params))
    flash[:notice] = l(:notice_successful_update)
    redirect_to sanan_agile_global_settings_path
  end
end
