# frozen_string_literal: true

module SananAgile
  class IssueShowHook < Redmine::Hook::ViewListener
    render_on :view_issues_show_details_bottom, partial: 'sanan_agile/issue_release'
  end
end
