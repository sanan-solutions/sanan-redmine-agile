class SananAgile::GlobalModalHook < Redmine::Hook::ViewListener
  def view_layouts_base_html_head(context = {})
    # cfg = get_project_setting(context)
    # return '' unless %w(1 true yes on).include?(cfg['sanan_agile_enabled'].to_s.strip.downcase)

    tags = <<-HTML
      <script src="/javascripts/jstoolbar/jstoolbar.js"></script>
      <script src="/javascripts/jstoolbar/common_mark.js"></script>
      <script src="/javascripts/jstoolbar/textile.js"></script>
      <script src="/javascripts/jstoolbar/lang/jstoolbar-en.js"></script>
      <script src="/javascripts/tribute-5.1.3.min.js"></script>
      <script src="/javascripts/context_menu.js"></script>
      <script src="/javascripts/attachments.js"></script>
    HTML
    tags.html_safe
  end

  # Chèn modal vào cuối <body>
  def view_layouts_base_body_bottom(context = {})
    cfg = get_project_setting(context)
    enable = sanan_truthy?(cfg['sanan_agile_enabled'])

    modal_js = if enable
      '/plugin_assets/sanan_redmine_agile/javascripts/sanan_global_modal.js'
    else
      '/plugin_assets/sanan_redmine_agile/javascripts/sanan_global_modal_mini.js'
    end

    modal_css = if enable
      '/plugin_assets/sanan_redmine_agile/stylesheets/sanan_redmine_agile.css'
    else
      '/plugin_assets/sanan_redmine_agile/stylesheets/sanan_redmine_agile_mini.css'
    end

    modal_html = <<-HTML
      <div id="global-modal" class="global-modal" style="display: none;">
        <div class="global-modal__content">
          <div class="content__header">
            <h2 class="header__title">Edit Issue</h2>
            <div class="header__close-btn">&times;</div>
          </div>
          <div id="glocal-modal-content-body" class="content__body">
            <p>Loading content...</p>
          </div>
          <button id="modal-scroll-top" class="scroll-top-btn" aria-label="Scroll to top">
          ↑
          </button>
        </div>
      </div>
  
      <script src="#{modal_js}"></script>
      <script src="/plugin_assets/sanan_redmine_agile/javascripts/helper.js"></script>
      <link rel="stylesheet" href="#{modal_css}" />
      <link rel="stylesheet" href="/plugin_assets/sanan_redmine_agile/stylesheets/helper.css" />
    HTML
    modal_html.html_safe
  end

  private
  def get_project_setting(ctx={})
    c = ctx[:controller]
    return '' unless c && %w[agile_boards issues releases].include?(c.controller_name)

    project = ctx[:project] ||
              c.instance_variable_get(:@project) ||
              begin
                pid = c.params[:project_id] || c.params[:id]
                Project.find_by(id: pid) if pid.present?
              end
    return '' unless project

    cfg = SananAgile::ProjectSettings.load(project.id) || {}
    return cfg
  end

  def sanan_truthy?(v)
    %w[1 true yes on].include?(v.to_s.strip.downcase)
  end
end
