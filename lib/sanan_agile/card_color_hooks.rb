# frozen_string_literal: true
module SananAgile
  class CardColorHooks < Redmine::Hook::ViewListener
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
      return '' unless %w(1 true yes on).include?(cfg['sanan_agile_enabled'].to_s.strip.downcase)

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

    private
    def normalize_hex(h)
      s = h.to_s.strip
      s = "##{s}" unless s.start_with?('#')
      return '#ffffff' unless s =~ /^#([A-Fa-f0-9]{6})$/
      s
    end
  end
end
