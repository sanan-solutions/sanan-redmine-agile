# frozen_string_literal: true
require_dependency File.expand_path('lib/sanan_agile/issue_patch', __dir__)
require_dependency File.expand_path('lib/sanan_agile/issue_query_patch', __dir__)
require_dependency File.expand_path('lib/sanan_agile/queries_helper_patch', __dir__)
require_dependency File.expand_path('lib/sanan_agile/project_settings', __dir__)
require_dependency File.expand_path('lib/sanan_agile/projects_helper_patch.rb', __dir__)
require_dependency File.expand_path('lib/sanan_agile/version_patch', __dir__)
require_dependency File.expand_path('lib/sanan_agile/versions_controller_patch', __dir__)
require_dependency File.expand_path('lib/sanan_agile/issue_card_hook', __dir__)
require_dependency File.expand_path('lib/sanan_agile/issue_show_hook', __dir__)
require_dependency File.expand_path('lib/sanan_agile/version_show_hook', __dir__)
require_dependency File.expand_path('lib/sanan_agile/assets_hook', __dir__)
require_dependency File.expand_path('lib/sanan_agile/global_modal_hook', __dir__)

Rails.application.config.to_prepare do
  require_dependency 'releases_controller'
  require_dependency File.expand_path('lib/sanan_agile/issue_query_patch', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/queries_helper_patch', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/sprint_report/calculator', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/sprint_report/closer', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/sprint_report/history', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/backlog_query', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/intake_source', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/intake_backlog_query', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/intake_pull', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/intake_candidates', __dir__)
  require_dependency File.expand_path('lib/sanan_agile/versions_controller_patch', __dir__)
  unless VersionsController.ancestors.include?(SananAgile::VersionsControllerPatch)
    VersionsController.prepend(SananAgile::VersionsControllerPatch)
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
               { backlogs: [:show] },
               require: :member

    permission :manage_backlog,
               { backlogs: [:reorder, :create_sprint, :start_sprint, :complete_sprint,
                            :create_issue, :create_epic, :bulk_move, :attach_to_release,
                            :bulk_update_status, :bulk_update_priority, :bulk_update_tracker,
                            :bulk_destroy, :quick_update, :pull_intake, :update_sprint_quota] },
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
                            :reorder, :update_issue_status, :change_state, :update, :edit, :destroy] }
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
           cfg['backlog_enabled'].to_s != '0'
       }

  menu :project_menu,
       :cs_backlog,
       { controller: 'cs_backlogs', action: 'show' },
       caption: :label_cs_backlog,
       after: :backlog,
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
