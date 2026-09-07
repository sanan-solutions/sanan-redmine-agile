# frozen_string_literal: true

module SananAgile
  module VersionsControllerPatch
    def update
      if params[:version]
        attributes = params[:version].dup
        attributes.delete('sharing') unless @version.allowed_sharings.include?(attributes['sharing'])
        was_open = @version.status != 'closed'
        @version.safe_attributes = attributes
        if @version.save
          respond_to do |format|
            format.html do
              flash[:notice] = l(:notice_successful_update)
              if was_open && @version.status == 'closed' &&
                 User.current.allowed_to?(:view_sprint_reports, @project) &&
                 SananAgile::ProjectSettings.load(@project.id)['sanan_agile_enabled'].to_s == '1'
                redirect_to project_sprint_report_path(@project, @version)
              else
                redirect_back_or_default settings_project_path(@project, tab: 'versions')
              end
            end
            format.api { render_api_ok }
          end
        else
          respond_to do |format|
            format.html { render action: 'edit' }
            format.api { render_validation_errors(@version) }
          end
        end
      end
    end
  end
end

VersionsController.prepend(SananAgile::VersionsControllerPatch) \
  unless VersionsController.ancestors.include?(SananAgile::VersionsControllerPatch)
