# frozen_string_literal: true

module SananAgile
  class IssueShowHook < Redmine::Hook::ViewListener
    # Một render_on duy nhất — Redmine define_method nên gọi nhiều lần sẽ bị ghi đè.
    render_on :view_issues_show_details_bottom, partial: 'sanan_agile/issue_details_bottom'
  end
end
