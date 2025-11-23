# frozen_string_literal: true
require_dependency File.expand_path('lib/sanan_agile/issue_patch', __dir__)
require_dependency File.expand_path('lib/sanan_agile/version_picker', __dir__)
require_dependency File.expand_path('lib/sanan_agile/project_settings', __dir__)
require_dependency File.expand_path('lib/sanan_agile/projects_helper_patch.rb', __dir__)

require_dependency File.expand_path('lib/sanan_agile/agile_data', __dir__)
require_dependency File.expand_path('lib/sanan_agile/hide_agile_sp_field_hook', __dir__)
require_dependency File.expand_path('lib/sanan_agile/hooks', __dir__)
require_dependency File.expand_path('lib/sanan_agile/assets_hook', __dir__)
require_dependency File.expand_path('lib/sanan_agile/card_color_hooks', __dir__)
require_dependency File.expand_path('lib/sanan_agile/global_modal', __dir__)
require_dependency File.expand_path('lib/sanan_agile/version_patch', __dir__)

Rails.application.config.to_prepare do
  require_dependency 'releases_controller'
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
  end

  project_module :releases do
    # Quyền xem danh sách/chi tiết, gọi datasource picker, và panel phải
    permission :view_releases,
               { releases: [:index, :show, :issues_search, :issue_panel,] },
               require: :member

    # Quyền thao tác quản trị: tạo, gắn/ tháo issues, đổi trạng thái, reorder, quick status
    permission :manage_releases,
               { releases: [:new, :create, :attach_issues, :detach_item,
                            :reorder, :update_issue_status, :change_state, :update,:edit] }
  end

    # === Menu ở Project ===
  # Hiện tab "Releases" khi module :releases bật ở project
  menu :project_menu,
       :releases,
       { controller: 'releases', action: 'index' },
       caption: 'Releases',
       after: :agile,
       param: :project_id,
       if: Proc.new { |project| User.current.allowed_to?(:view_releases, project) && SananAgile::ProjectSettings.load(project.id)['sanan_agile_enabled'].to_s == '1' }

  # Nếu bạn muốn menu luôn hiện với mọi member khi module được bật, bỏ `if: ...` đi.

  # Tạo plugin settings key hợp lệ: Setting.plugin_sanan_redmine_agile (Hash)
  settings default: {}, partial: nil
end
