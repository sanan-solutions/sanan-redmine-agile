# frozen_string_literal: true

require_dependency 'queries_helper'

module SananAgile
  module QueriesHelperPatch
    def self.included(base)
      base.send(:include, InstanceMethods)

      base.class_eval do
        unless method_defined?(:column_value_without_sanan_release)
          alias_method :column_value_without_sanan_release, :column_value
          alias_method :column_value, :column_value_with_sanan_release
        end
      end
    end

    module InstanceMethods
      def column_value_with_sanan_release(column, item, value)
        if column.name == :sanan_release_version && item.is_a?(Issue)
          release = value.is_a?(ReleaseVersion) ? value : ReleaseVersion.for_issue(item)
          return l(:label_not_in_release) unless release

          project = item.project
          if project && User.current.allowed_to?(:view_releases, project)
            return link_to(h(release.name), project_release_path(project, release))
          end

          return h(release.name)
        end

        column_value_without_sanan_release(column, item, value)
      end
    end
  end
end

unless QueriesHelper.included_modules.include?(SananAgile::QueriesHelperPatch)
  QueriesHelper.send(:include, SananAgile::QueriesHelperPatch)
end
