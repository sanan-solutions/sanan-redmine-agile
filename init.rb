# frozen_string_literal: true
require_dependency File.expand_path('lib/sanan_agile/agile_data_association', __dir__)
require_dependency File.expand_path('lib/sanan_agile/agile_story_points', __dir__)
require_dependency File.expand_path('lib/sanan_agile/issue_patch', __dir__)
require_dependency File.expand_path('lib/sanan_agile/issue_query_patch', __dir__)
require_dependency File.expand_path('lib/sanan_agile/queries_helper_patch', __dir__)
require_dependency File.expand_path('lib/sanan_agile/project_settings', __dir__)
require_dependency File.expand_path('lib/sanan_agile/commit_lock', __dir__)
require_dependency File.expand_path('lib/sanan_agile/sprint_commit', __dir__)
require_dependency File.expand_path('lib/sanan_agile/dod_sprint', __dir__)
require_dependency File.expand_path('lib/sanan_agile/projects_helper_patch.rb', __dir__)
require_dependency File.expand_path('lib/sanan_agile/version_patch', __dir__)
require_dependency File.expand_path('lib/sanan_agile/versions_controller_patch', __dir__)
require_dependency File.expand_path('lib/sanan_agile/issue_card_hook', __dir__)
require_dependency File.expand_path('lib/sanan_agile/issue_show_hook', __dir__)
require_dependency File.expand_path('lib/sanan_agile/issue_sp_hook', __dir__)
require_dependency File.expand_path('lib/sanan_agile/sprint_sp_history', __dir__)
require_dependency File.expand_path('lib/sanan_agile/sp_total_formula', __dir__)
require_dependency File.expand_path('lib/sanan_agile/velocity', __dir__)
require_dependency File.expand_path('lib/sanan_agile/issues_helper_patch', __dir__)
require_dependency File.expand_path('lib/sanan_agile/version_show_hook', __dir__)
require_dependency File.expand_path('lib/sanan_agile/assets_hook', __dir__)
require_dependency File.expand_path('lib/sanan_agile/global_modal_hook', __dir__)

Rails.application.config.to_prepare do
  require_dependency File.expand_path('lib/sanan_agile/agile_data_association', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/board_default_filters', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/agile_story_points', __dir__)
  SananAgile::AgileDataAssociation.ensure!

  require_dependency File.expand_path('lib/sanan_agile/issue_patch', __dir__)
  unless Issue.included_modules.include?(SananAgile::IssuePatch)
    Issue.send(:include, SananAgile::IssuePatch)
  end
  begin
    if defined?(RedmineAgile::Patches::IssuePatch) &&
       !Issue.included_modules.include?(RedmineAgile::Patches::IssuePatch)
      Issue.send(:include, RedmineAgile::Patches::IssuePatch)
    end
  rescue StandardError => e
    Rails.logger.error "[sanan_redmine_agile] RedmineAgile IssuePatch: #{e.class}: #{e.message}"
  end
  if defined?(RedmineChecklists::Patches::IssuePatch) &&
     !Issue.included_modules.include?(RedmineChecklists::Patches::IssuePatch)
    begin
      Issue.send(:include, RedmineChecklists::Patches::IssuePatch)
    rescue StandardError => e
      Rails.logger.error "[sanan_redmine_agile] checklists IssuePatch: #{e.class}: #{e.message}"
    end
  end
  SananAgile::AgileDataAssociation.ensure!
  SananAgile::AgileStoryPoints.install!

  require_dependency 'releases_controller'
  require_dependency File.expand_path('lib/sanan_agile/issue_query_patch', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/queries_helper_patch', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/issues_helper_patch', __dir__)
  SananAgile::IssuesHelperPatch.apply!
  require_dependency File.expand_path('lib/sanan_agile/sprint_sp_history', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/sp_total_formula', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/issue_sp_hook', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/commit_lock', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/sprint_commit', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/dod_sprint', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/sprint_report/calculator', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/sprint_report/closer', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/sprint_report/history', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/velocity', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/roadmap_dependencies', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/roadmap_query', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/roadmap_capacity', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/roadmap_baseline', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/roadmap_product', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/backlog_query', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/priority_icon', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/board_backlog', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/product_backlog', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/intake_source', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/intake_backlog_query', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/intake_pull', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/intake_candidates', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/intake_queue_health', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/versions_controller_patch', __dir__)
  unless VersionsController.ancestors.include?(SananAgile::VersionsControllerPatch)
    VersionsController.prepend(SananAgile::VersionsControllerPatch)
  end
  begin
    require_dependency 'agile_boards_controller'
    require_dependency File.expand_path('lib/sanan_agile/agile_boards_controller_patch', __dir__)
    SananAgile::AgileStoryPoints.install!
    SananAgile::AgileStoryPoints.install_controller!
  rescue LoadError
  end
rescue LoadError => e
  Rails.logger.error "[sanan_redmine_agile] to_prepare LoadError: #{e.message}"
  raise
end

Redmine::Plugin.register :sanan_redmine_agile do
  name        'Sanan Redmine Agile'
  author      'SanAn'
  description 'Auto set Target version / Custom field when issue reaches the configured status (per-project settings).'
  version     '1.0.0'

  # Bật/tắt như một project module để kiểm soát quyền hiển thị tab
  project_module :sanan_agile do
    permission :manage_sanan_agile_settings,
               { 'sanan_agile/project_settings' => [:update] },
               require: :member

    permission :view_sprint_reports,
               { sprint_reports: [:show] },
               require: :member

    permission :view_backlog,
               { backlogs: [:show, :sections, :issues], 'sanan_agile/board_backlog' => [:index] },
               require: :member

    permission :manage_backlog,
               { backlogs: [:reorder, :create_sprint, :update_sprint, :destroy_sprint, :start_sprint, :complete_sprint,
                            :create_issue, :create_epic, :bulk_move, :attach_to_release,
                            :bulk_update_status, :bulk_update_priority, :bulk_update_tracker,
                            :bulk_destroy, :quick_update, :pull_intake, :update_sprint_quota],
                 'sanan_agile/board_backlog' => [:pull, :push] },
               require: :member

    permission :view_roadmap,
               { roadmaps: [:show, :data] },
               require: :member

    permission :manage_roadmap,
               { roadmaps: [:move, :update_health, :update_span, :create_baseline, :destroy_baseline] },
               require: :member

    permission :view_cs_backlog,
               { cs_backlogs: [:show] },
               require: :member

    permission :manage_cs_backlog,
               { cs_backlogs: [:create_issue, :quick_update] },
               require: :member

    permission :view_sale_backlog,
               { sale_backlogs: [:show] },
               require: :member

    permission :manage_sale_backlog,
               { sale_backlogs: [:create_issue, :quick_update] },
               require: :member
  end

  project_module :releases do
    # Quyền xem danh sách/chi tiết, gọi datasource picker, và panel phải
    permission :view_releases,
               { releases: [:index, :show, :issues_search, :issue_panel,] },
               require: :member

    # Quyền thao tác quản trị: tạo, gắn/ tháo issues, đổi trạng thái, reorder, quick status
    permission :manage_releases,
               { releases: [:new, :create, :attach_issues, :detach_item,
                            :reorder, :update_issue_status, :update_code_picked, :change_state, :update, :edit, :destroy] }
  end

    # === Menu ở Project ===
  # Hiện tab "Releases" khi module :releases bật ở project
  menu :project_menu,
       :backlog,
       { controller: 'backlogs', action: 'show' },
       caption: :label_backlog,
       after: :agile,
       param: :project_id,
       if: Proc.new { |project|
         cfg = SananAgile::ProjectSettings.load(project.id)
         User.current.allowed_to?(:view_backlog, project) &&
           cfg['sanan_agile_enabled'].to_s == '1' &&
           cfg['backlog_enabled'].to_s == '1'
       }

  menu :top_menu,
       :sanan_portfolio_roadmap,
       { controller: 'portfolio_roadmaps', action: 'show' },
       caption: :label_sanan_roadmap,
       after: :projects,
       if: Proc.new { User.current.logged? && User.current.allowed_to?(:view_roadmap, nil, global: true) }

  menu :project_menu,
       :sanan_roadmap,
       { controller: 'roadmaps', action: 'show' },
       caption: :label_sanan_roadmap,
       after: :backlog,
       param: :project_id,
       if: Proc.new { |project|
         cfg = SananAgile::ProjectSettings.load(project.id)
         User.current.allowed_to?(:view_roadmap, project) &&
           cfg['sanan_agile_enabled'].to_s == '1' &&
           cfg['roadmap_enabled'].to_s == '1'
       }

  menu :project_menu,
       :cs_backlog,
       { controller: 'cs_backlogs', action: 'show' },
       caption: :label_cs_backlog,
       after: :sanan_roadmap,
       param: :project_id,
       if: Proc.new { |project|
         cfg = SananAgile::ProjectSettings.load(project.id)
         User.current.allowed_to?(:view_cs_backlog, project) &&
           cfg['sanan_agile_enabled'].to_s == '1' &&
           cfg['cs_backlog_enabled'].to_s == '1'
       }

  menu :project_menu,
       :sale_backlog,
       { controller: 'sale_backlogs', action: 'show' },
       caption: :label_sale_backlog,
       after: :cs_backlog,
       param: :project_id,
       if: Proc.new { |project|
         cfg = SananAgile::ProjectSettings.load(project.id)
         User.current.allowed_to?(:view_sale_backlog, project) &&
           cfg['sanan_agile_enabled'].to_s == '1' &&
           cfg['sale_backlog_enabled'].to_s == '1'
       }

  menu :project_menu,
       :releases,
       { controller: 'releases', action: 'index' },
       caption: 'Releases',
       after: :sale_backlog,
       param: :project_id,
       if: Proc.new { |project| User.current.allowed_to?(:view_releases, project) && SananAgile::ProjectSettings.load(project.id)['sanan_agile_enabled'].to_s == '1' }

  # Nếu bạn muốn menu luôn hiện với mọi member khi module được bật, bỏ `if: ...` đi.

  # Tạo plugin settings key hợp lệ: Setting.plugin_sanan_redmine_agile (Hash)
  settings default: {}, partial: nil
end

# Project menu order (see SananAgile::ProjectMenuOrder): Gantt, Calendar, Roadmap, Product Roadmap, Backlog,
# CS Backlog, Sale Backlog, Issues, Agile board, Releases.
# (redmine_agile is loaded before this plugin, so its :agile item already exists here.)
require_dependency File.expand_path('lib/sanan_agile/project_menu_order', __dir__)
SananAgile::ProjectMenuOrder.apply!
