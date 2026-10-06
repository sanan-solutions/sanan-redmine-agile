# frozen_string_literal: true

module SananAgile
  class IssueSpHook < Redmine::Hook::ViewListener
    render_on :view_issues_form_details_bottom, partial: 'sanan_agile/issue_sp_form'
  end
end
