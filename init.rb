# frozen_string_literal: true
require_dependency File.expand_path('lib/sanan_agile/issue_patch', __dir__)
require_dependency File.expand_path('lib/sanan_agile/version_picker', __dir__)
require_dependency File.expand_path('lib/sanan_agile/project_settings', __dir__)
require_dependency File.expand_path('lib/sanan_agile/projects_helper_patch.rb', __dir__)

require_dependency File.expand_path('lib/sanan_agile/agile_data', __dir__)
require_dependency File.expand_path('lib/sanan_agile/hide_agile_sp_field_hook', __dir__)
require_dependency File.expand_path('lib/sanan_agile/hooks', __dir__)

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

  # Tạo plugin settings key hợp lệ: Setting.plugin_sanan_redmine_agile (Hash)
  settings default: {}, partial: nil
end
