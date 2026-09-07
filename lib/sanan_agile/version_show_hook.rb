# frozen_string_literal: true

class SananAgile::VersionShowHook < Redmine::Hook::ViewListener
  render_on :view_versions_show_contextual,
            partial: 'sanan_agile/version_sprint_report_link'
end
