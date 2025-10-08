# frozen_string_literal: true
module SananAgile
  module ProjectsHelperPatch
    def self.included(base)
      base.class_eval do
        # Alias lại hàm project_settings_tabs
        def project_settings_tabs_with_sanan
          tabs = project_settings_tabs_without_sanan
          tabs << {
            action: :edit_project,
            name: 'sanan_agile',
            label: 'label_sanan_agile_settings',
            partial: 'sanan_agile/project_settings/tab'
          }
          tabs
        end

        unless method_defined?(:project_settings_tabs_without_sanan)
          alias_method :project_settings_tabs_without_sanan, :project_settings_tabs
          alias_method :project_settings_tabs, :project_settings_tabs_with_sanan
        end
      end
    end
  end
end

unless ProjectsHelper.included_modules.include?(SananAgile::ProjectsHelperPatch)
  ProjectsHelper.send(:include, SananAgile::ProjectsHelperPatch)
end
