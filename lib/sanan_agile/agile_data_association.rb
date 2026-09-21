# frozen_string_literal: true

require_dependency File.expand_path('agile_story_points', __dir__)

module SananAgile
  module AgileBoardsHelperPatch
    def story_points_value(query, issue)
      SananAgile::AgileDataAssociation.ensure!
      return unless query.has_column_name?(:story_points) && RedmineAgile.use_story_points?

      sp = if issue.respond_to?(:story_points)
             issue.story_points
           else
             issue.try(:agile_data).try(:story_points)
           end
      sp.to_f if sp
    end

    def estimated_value(issue)
      SananAgile::AgileDataAssociation.ensure!
      super
    rescue NoMethodError
      (issue.try(:agile_data).try(:story_points) || issue.try(:estimated_hours) || 0).to_f
    end
  end

  module AgileQueryAssociationPatch
    def issues(options = {})
      SananAgile::AgileDataAssociation.ensure!
      super
    end
  end

  module AgileDataAssociation
    module_function

    def ensure!
      ensure_agile_data!
      ensure_checklists!
      ensure_agile_query_patch!
      SananAgile::AgileStoryPoints.install! if defined?(SananAgile::AgileStoryPoints)
    end

    def ensure_agile_boards_helper!
      return unless defined?(AgileBoardsHelper)
      return if AgileBoardsHelper.ancestors.include?(SananAgile::AgileBoardsHelperPatch)

      AgileBoardsHelper.prepend(SananAgile::AgileBoardsHelperPatch)
    end

    def ensure_agile_query_patch!
      return unless defined?(AgileQuery)
      return if AgileQuery.ancestors.include?(SananAgile::AgileQueryAssociationPatch)

      AgileQuery.prepend(SananAgile::AgileQueryAssociationPatch)
    end

    def ensure_agile_data!
      return unless defined?(Issue)

      unless defined?(AgileData)
        begin
          require_dependency 'agile_data'
        rescue LoadError
          return
        end
      end
      return unless defined?(AgileData)

      unless Issue.reflect_on_association(:agile_data)
        Issue.class_eval do
          has_one :agile_data, class_name: 'AgileData', dependent: :destroy
        end
      end

      restore_agile_issue_patch!

      if Issue.method_defined?(:agile_data_with_default) &&
         !Issue.method_defined?(:agile_data_without_default)
        Issue.class_eval do
          alias_method :agile_data_without_default, :agile_data
          alias_method :agile_data, :agile_data_with_default
        end
      end

      unless Issue.respond_to?(:sorted_by_rank)
        Issue.class_eval do
          scope :sorted_by_rank, lambda {
            eager_load(:agile_data).order(Arel.sql("COALESCE(#{AgileData.table_name}.position, 999999)"))
          }
        end
      end

      unless Issue.method_defined?(:story_points)
        Issue.class_eval do
          def story_points
            @story_points ||= agile_data.try(:story_points)
          end
        end
      end
    end

    def restore_agile_issue_patch!
      unless defined?(RedmineAgile::Patches::IssuePatch)
        begin
          require_dependency 'redmine_agile/patches/issue_patch'
        rescue LoadError
          return
        end
      end
      return unless defined?(RedmineAgile::Patches::IssuePatch)
      return if Issue.included_modules.include?(RedmineAgile::Patches::IssuePatch)

      Issue.send(:include, RedmineAgile::Patches::IssuePatch)
    rescue StandardError => e
      Rails.logger&.error("[sanan_redmine_agile] agile IssuePatch: #{e.class}: #{e.message}")
    end

    def ensure_checklists!
      return unless defined?(Issue)

      unless defined?(Checklist)
        begin
          require_dependency 'checklist'
        rescue LoadError
          return
        end
      end
      return unless defined?(Checklist)

      if defined?(RedmineChecklists::Patches::IssuePatch) &&
         !Issue.included_modules.include?(RedmineChecklists::Patches::IssuePatch)
        begin
          Issue.send(:include, RedmineChecklists::Patches::IssuePatch)
        rescue StandardError => e
          Rails.logger&.error("[sanan_redmine_agile] checklists IssuePatch: #{e.class}: #{e.message}")
        end
      end

      return if Issue.reflect_on_association(:checklists)

      Issue.class_eval do
        has_many :checklists, -> { order("#{Checklist.table_name}.position") },
                 class_name: 'Checklist', dependent: :destroy, inverse_of: :issue
      end
    end
  end
end
