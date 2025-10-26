# frozen_string_literal: true
class SananAgile::AssetsHook < Redmine::Hook::ViewListener
  def view_layouts_base_html_head(ctx = {})
    c = ctx[:controller]
    return '' unless c && c.controller_name == 'agile_boards'

    project = ctx[:project] ||
              c.instance_variable_get(:@project) ||
              begin
                pid = c.params[:project_id] || c.params[:id]
                Project.find_by(id: pid) if pid.present?
              end
    return '' unless project

    cfg = SananAgile::ProjectSettings.load(project.id) || {}
    return '' unless sanan_truthy?(cfg['sanan_agile_enabled']) # <<< chỉ khi bật

    css = stylesheet_link_tag 'sanan_agile_board_table', plugin: 'sanan_redmine_agile'
    js_scroll  = javascript_include_tag 'sanan_board_table_scroll_sync', plugin: 'sanan_redmine_agile'
    js_inline = javascript_include_tag 'sanan_inline_card_refresh', plugin: 'sanan_redmine_agile'

    (css + js_scroll + js_inline).html_safe
  end

  private

  # Chấp nhận: 1/true/yes/on (không phân biệt hoa thường)
  def sanan_truthy?(v)
    %w[1 true yes on].include?(v.to_s.strip.downcase)
  end
end
