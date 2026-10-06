# frozen_string_literal: true

# Zeitwerk reload drops RedmineAgile IssuePatch methods (story_points).
# Re-install on Issue + AgileBoardsHelper every request — do not gate on method_defined?
module SananAgile
  module AgileStoryPoints
    module_function

    def install!
      install_on_issue!
      install_on_helper!
      install_controller!
    end

    # Issue#story_points (redmine_agile cards, charts, column sums) = the "This sprint" Total of the ticket.
    def install_on_issue!
      return unless defined?(Issue)

      Issue.class_eval do
        def story_points
          return nil unless project_id

          cfg = SananAgile::ProjectSettings.load(project_id)
          SananAgile::IssueSp.total_of(SananAgile::IssueSp.values(self, cfg, :sprint), cfg)
        end
      end
    end

    def install_on_helper!
      unless defined?(AgileBoardsHelper)
        begin
          require_dependency 'agile_boards_helper'
        rescue LoadError
          return
        end
      end
      return unless defined?(AgileBoardsHelper)

      AgileBoardsHelper.class_eval do
        def story_points_value(query, issue)
          return unless query.has_column_name?(:story_points) && RedmineAgile.use_story_points?

          sp = sanan_issue_story_points(issue)
          sp.to_f if sp
        end

        def header_th(name, rowspan = 1, colspan = 1, leaf = nil)
          th_attributes = {}
          count_tag = ''.html_safe
          hours_tag = ''.html_safe
          if leaf
            th_attributes[:'data-column-id'] = leaf.id
            issue_count = leaf.instance_variable_get('@issue_count') || 0
            count_tag = " (#{content_tag(:span, issue_count.to_i, class: 'count')})".html_safe

            story_points_count = leaf.instance_variable_get('@story_points') || 0
            hours_count = leaf.instance_variable_get('@estimated_hours_sum') || 0
            values = []
            values << format('%.2fh', hours_count.to_f) if hours_count.to_f > 0
            values << "#{story_points_count}sp" if story_points_count.to_f > 0
            if values.present?
              hours_tag = content_tag(:span, " #{values.join('/')}".html_safe,
                                      class: 'hours', title: l(:field_estimated_hours))
            end
          end
          content_tag :th, h(name) + count_tag + hours_tag, th_attributes
        end

        def render_issue_card_hours(query, issue)
          hours = []
          hours << '%.2f' % issue.total_spent_hours.to_f if query.has_column_name?(:spent_hours) && issue.total_spent_hours.to_f > 0
          hours << '%.2f' % issue.estimated_hours.to_f if query.has_column_name?(:estimated_hours) && issue.estimated_hours
          hours = [hours.join('/') + 'h'] unless hours.blank?
          sp = sanan_issue_story_points(issue)
          hours << "#{sp}sp" if RedmineAgile.use_story_points? && query.has_column_name?(:story_points) && sp

          content_tag(:span, "(#{hours.join('/')})", class: 'hours') unless hours.blank?
        end

        def estimated_value(issue)
          return (sanan_issue_story_points(issue) || 0).to_f if RedmineAgile.use_story_points?

          issue.estimated_hours.to_f || 0
        end

        def sanan_issue_story_points(issue)
          issue&.story_points
        end
      end
    end

    def install_controller!
      return unless defined?(AgileBoardsController)

      unless AgileBoardsController.ancestors.include?(SananAgile::AgileBoardsControllerPatch)
        AgileBoardsController.prepend(SananAgile::AgileBoardsControllerPatch)
      end
      unless AgileBoardsController._helpers.included_modules.include?(BacklogsHelper)
        AgileBoardsController.helper :backlogs
      end
    end
  end
end
