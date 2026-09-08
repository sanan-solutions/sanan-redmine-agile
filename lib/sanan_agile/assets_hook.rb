# frozen_string_literal: true
class SananAgile::AssetsHook < Redmine::Hook::ViewListener
  def view_layouts_base_html_head(ctx = {})
    c = ctx[:controller]
    return '' unless c

    project = ctx[:project] ||
              c.instance_variable_get(:@project) ||
              c.instance_variable_get(:@issue)&.try(:project) ||
              begin
                pid = c.params[:project_id]
                pid ||= c.params[:id] if c.controller_name == 'agile_boards'
                Project.find_by(id: pid) || Project.find_by(identifier: pid) if pid.present?
              end
    return '' unless project

    cfg = SananAgile::ProjectSettings.load(project.id) || {}
    return '' unless sanan_truthy?(cfg['sanan_agile_enabled']) # <<< chỉ khi bật

    case c.controller_name
    when 'agile_boards'
      agile_board_assets(cfg)
    when 'issues'
      c.action_name == 'show' ? issue_show_assets : ''
    when 'backlogs', 'cs_backlogs', 'sale_backlogs'
      backlog_assets
    else
      ''
    end
  end

  private

  def backlog_assets
    (
      stylesheet_link_tag('backlog', plugin: 'sanan_redmine_agile') +
      javascript_include_tag('backlog', plugin: 'sanan_redmine_agile')
    ).html_safe
  end

  def agile_board_assets(cfg)
    all_css = ''
    all_css += stylesheet_link_tag 'sanan_agile_board_table', plugin: 'sanan_redmine_agile'
    all_css += stylesheet_link_tag 'agile_release_badges', plugin: 'sanan_redmine_agile'
    all_css += stylesheet_link_tag 'agile_intake_badges', plugin: 'sanan_redmine_agile'
    if cfg['story_point_cfid'].present?
      all_css += stylesheet_link_tag 'hide_agile_sp', plugin: 'sanan_redmine_agile'
    end

    all_js = ''
    all_js += javascript_include_tag 'agile_core', plugin: 'sanan_redmine_agile'
    all_js += javascript_include_tag 'sanan_board_table_scroll_sync', plugin: 'sanan_redmine_agile'
    all_js += javascript_include_tag 'sanan_inline_card_refresh', plugin: 'sanan_redmine_agile'
    all_js += javascript_include_tag 'agile_release_badges', plugin: 'sanan_redmine_agile'
    all_js += javascript_include_tag 'agile_intake_badges', plugin: 'sanan_redmine_agile'
    all_js += issue_card_color_js(cfg)

    (all_css + all_js).html_safe
  end

  def issue_show_assets
    stylesheet_link_tag('agile_release_badges', plugin: 'sanan_redmine_agile').html_safe
  end

  # Chấp nhận: 1/true/yes/on (không phân biệt hoa thường)
  def sanan_truthy?(v)
    %w[1 true yes on].include?(v.to_s.strip.downcase)
  end

  def normalize_hex(h)
    s = h.to_s.strip
    s = "##{s}" unless s.start_with?('#')
    return '#ffffff' unless s =~ /^#([A-Fa-f0-9]{6})$/
    s
  end

  def issue_card_color_js(cfg)
    raw = (cfg['card_color_tracker_map'] || {})
    return '' if raw.blank?

    tracker_colors = {}
    raw.each do |id, hex|
      next if hex.to_s.strip.empty?
      tr = Tracker.find_by(id: id.to_i)
      next unless tr
      color = normalize_hex(hex)
      tracker_colors[tr.name] = color
    end
    return '' if tracker_colors.empty?

    mode = (cfg['card_color_tracker_mode'].presence || 'body').to_s.downcase
    mode = %w(body border).include?(mode) ? mode : 'body'

    js = <<-JS
    <script id="sanan-tracker-colors-data">
      window.SANAN_TRACKER_COLORS = #{tracker_colors.to_json};
      window.SANAN_TRACKER_COLOR_MODE = #{mode.to_json};
    </script>
    JS
    js + javascript_include_tag('sanan_card_colors_tracker', plugin: 'sanan_redmine_agile')
  end
end
