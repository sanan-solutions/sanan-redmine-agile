# frozen_string_literal: true

module SananAgile
  class IssueSpHook < Redmine::Hook::ViewListener
    render_on :view_issues_form_details_bottom, partial: 'sanan_agile/issue_sp_form'

    def controller_issues_new_before_save(context = {})
      assign_size(context)
    end

    def controller_issues_edit_before_save(context = {})
      assign_size(context)
    end

    private

    def assign_size(context)
      issue = context[:issue]
      params = context[:params]
      return unless issue && params

      cfg = SananAgile::ProjectSettings.load(issue.project_id) if issue.project_id
      return if cfg && SananAgile::SpTotalFormula.subtask?(issue, cfg) # personal SP only

      size = params[:sanan_sp_size]
      issue.sanan_sp_size_attrs = size unless size.nil?

      sprint = params[:sanan_sp_sprint]
      issue.sanan_sp_sprint_attrs = sprint unless sprint.nil?

      SananAgile::SpTotalFormula.apply_issue!(issue, cfg) if cfg
    end
  end
end
