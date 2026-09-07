# frozen_string_literal: true

require_dependency 'issue_query'

module SananAgile
  module IssueQueryPatch
    def self.included(base)
      base.send(:include, InstanceMethods)

      base.class_eval do
        unless available_columns.any? { |c| c.name == :sanan_release_version }
          add_available_column QueryColumn.new(
            :sanan_release_version,
            caption: :label_release_version,
            sortable: "#{ReleaseVersion.table_name}.name"
          )
        end

        unless method_defined?(:issues_without_sanan_release)
          alias_method :issues_without_sanan_release, :issues
          alias_method :issues, :issues_with_sanan_release
        end

        unless method_defined?(:joins_for_order_statement_without_sanan_release)
          alias_method :joins_for_order_statement_without_sanan_release, :joins_for_order_statement
          alias_method :joins_for_order_statement, :joins_for_order_statement_with_sanan_release
        end

        unless method_defined?(:initialize_available_filters_without_sanan_release)
          alias_method :initialize_available_filters_without_sanan_release, :initialize_available_filters
          alias_method :initialize_available_filters, :initialize_available_filters_with_sanan_release
        end
      end
    end

    module InstanceMethods
      def issues_with_sanan_release(options = {})
        issues = issues_without_sanan_release(options)
        ReleaseVersion.preload_for_issues!(issues) if has_column?(:sanan_release_version)
        issues
      end

      def joins_for_order_statement_with_sanan_release(order_options)
        joins = joins_for_order_statement_without_sanan_release(order_options)
        return joins if order_options.blank?
        return joins unless order_options.include?(ReleaseVersion.table_name)

        release_join = "LEFT OUTER JOIN #{ReleaseItem.table_name}" \
                       " ON #{ReleaseItem.table_name}.issue_id = #{Issue.table_name}.id" \
                       " LEFT OUTER JOIN #{ReleaseVersion.table_name}" \
                       " ON #{ReleaseVersion.table_name}.id = #{ReleaseItem.table_name}.release_version_id"
        [joins, release_join].compact.join(' ')
      end

      def initialize_available_filters_with_sanan_release
        initialize_available_filters_without_sanan_release
        add_available_filter(
          'sanan_release_version_id',
          type: :list_optional,
          name: l(:label_release_version),
          values: lambda { sanan_release_version_filter_values }
        )
      end

      # Called by Query#statement via sql_for_<field>_field
      def sql_for_sanan_release_version_id_field(_field, operator, value)
        issue_table = Issue.table_name
        item_table = ReleaseItem.table_name

        case operator
        when '*', '!*'
          cond = sanan_release_match_condition(nil)
          operator == '*' ? cond : "NOT (#{cond})"
        when '=', '!'
          ids = Array(value).map(&:to_i).reject(&:zero?).uniq
          return (operator == '=' ? '1=0' : '1=1') if ids.empty?

          cond = sanan_release_match_condition(ids)
          operator == '=' ? cond : "NOT (#{cond})"
        else
          '1=1'
        end
      end

      private

      def sanan_release_version_filter_values
        scope = ReleaseVersion.order(:name)
        if project
          scope = scope.where(project_id: project.id)
        else
          allowed_ids = Project.where(
            Project.allowed_to_condition(User.current, :view_releases)
          ).pluck(:id)
          scope = scope.where(project_id: allowed_ids)
        end

        scope.map do |r|
          label = project ? r.name : "#{r.name} (#{r.project.try(:identifier)})"
          ["#{label} [#{r.state}]", r.id.to_s]
        end
      end

      # Issues directly in release_items, or standard-tracker children inheriting from parent.
      def sanan_release_match_condition(release_ids)
        item_table = ReleaseItem.table_name
        issue_table = Issue.table_name

        parent_ids_sql =
          if release_ids
            "SELECT #{item_table}.issue_id FROM #{item_table} " \
            "WHERE #{item_table}.release_version_id IN (#{release_ids.join(',')})"
          else
            "SELECT #{item_table}.issue_id FROM #{item_table}"
          end

        direct = "#{issue_table}.id IN (#{parent_ids_sql})"
        inherited = sanan_release_inherited_condition(parent_ids_sql)
        "(#{direct} OR #{inherited})"
      end

      def sanan_release_inherited_condition(parent_ids_sql)
        issue_table = Issue.table_name
        base = "#{issue_table}.parent_id IN (#{parent_ids_sql})"

        if project
          cfg = SananAgile::ProjectSettings.load(project.id)
          standard_ids = Array(cfg['standard_tracker']).map(&:to_i).reject(&:zero?)
          return '1=0' if standard_ids.blank?

          "#{base} AND #{issue_table}.tracker_id IN (#{standard_ids.join(',')})"
        else
          base
        end
      end
    end
  end
end

unless IssueQuery.included_modules.include?(SananAgile::IssueQueryPatch)
  IssueQuery.send(:include, SananAgile::IssueQueryPatch)
end
