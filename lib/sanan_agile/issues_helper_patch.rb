# frozen_string_literal: true

require_dependency 'issues_helper'

module SananAgile
  module IssuesHelperPatch
    SPRINT_DONE_SETTING_KEYS = %w[
      done_be_cfid done_fe_cfid done_qa_cfid
      dod_cfid code_done_cfid development_done_cfid uat_done_cfid
    ].freeze

    STORY_POINT_SETTING_KEYS = %w[
      story_point_cfid sp_be_cfid sp_fe_cfid sp_qa_cfid
    ].freeze

    def self.apply!
      return if IssuesHelper.instance_methods.include?(:sanan_issue_cf_tables_applied)

      IssuesHelper.module_eval do
        def sanan_issue_cf_tables_applied
          true
        end

        unless method_defined?(:render_half_width_custom_fields_rows_without_sanan_grouped_cfs)
          if method_defined?(:render_half_width_custom_fields_rows_without_sanan_sprint_done)
            alias_method :render_half_width_custom_fields_rows_without_sanan_grouped_cfs,
                         :render_half_width_custom_fields_rows_without_sanan_sprint_done
            alias_method :render_full_width_custom_fields_rows_without_sanan_grouped_cfs,
                         :render_full_width_custom_fields_rows_without_sanan_sprint_done
          else
            alias_method :render_half_width_custom_fields_rows_without_sanan_grouped_cfs,
                         :render_half_width_custom_fields_rows
            alias_method :render_full_width_custom_fields_rows_without_sanan_grouped_cfs,
                         :render_full_width_custom_fields_rows
          end
        end

        def render_half_width_custom_fields_rows(issue)
          values = issue.visible_custom_field_values.reject { |v| v.custom_field.full_width_layout? }
          values = sanan_reject_grouped_cf_values(issue, values)
          return if values.empty?

          half = (values.size / 2.0).ceil
          issue_fields_rows do |rows|
            values.each_with_index do |value, i|
              side = (i < half ? :left : :right)
              rows.send(
                side,
                custom_field_name_tag(value.custom_field),
                custom_field_value_tag(value),
                class: value.custom_field.css_classes
              )
            end
          end
        end

        def render_full_width_custom_fields_rows(issue)
          values = issue.visible_custom_field_values.select { |v| v.custom_field.full_width_layout? }
          values = sanan_reject_grouped_cf_values(issue, values)
          return if values.empty?

          html = ''.html_safe
          values.each do |value|
            attr_value_tag = custom_field_value_tag(value)
            next if attr_value_tag.blank?

            content =
              content_tag('hr') +
              content_tag('p', content_tag('strong', custom_field_name_tag(value.custom_field))) +
              content_tag('div', attr_value_tag, class: 'value')
            html << content_tag('div', content, class: "#{value.custom_field.css_classes} attribute")
          end
          html
        end

        def sanan_agile_enabled_for?(project)
          return false unless project

          cfg = SananAgile::ProjectSettings.load(project.id)
          %w[1 true yes on].include?(cfg['sanan_agile_enabled'].to_s.strip.downcase)
        end

        def sanan_sprint_done_cf_ids_for(project)
          return [] unless sanan_agile_enabled_for?(project)

          cfg = SananAgile::ProjectSettings.load(project.id)
          ids = SananAgile::IssuesHelperPatch::SPRINT_DONE_SETTING_KEYS.map { |k| cfg[k].to_i }.reject(&:zero?)
          IssueCustomField.sorted.each do |cf|
            next unless cf.name.to_s.match?(/in\s*sprint/i)

            ids << cf.id
          end
          ids.uniq
        end

        def sanan_story_point_cf_ids_for(project)
          return [] unless sanan_agile_enabled_for?(project)

          cfg = SananAgile::ProjectSettings.load(project.id)
          ids = SananAgile::IssuesHelperPatch::STORY_POINT_SETTING_KEYS.map { |k| cfg[k].to_i }.reject(&:zero?)

          # Prefer configured order: Total → BE → FE → TEST
          order = SananAgile::IssuesHelperPatch::STORY_POINT_SETTING_KEYS.map { |k| cfg[k].to_i }.reject(&:zero?)
          (order + ids).uniq
        end

        def sanan_sprint_done_values_for(issue)
          sanan_values_for_cf_ids(issue, sanan_sprint_done_cf_ids_for(issue&.project))
        end

        def sanan_story_point_values_for(issue)
          ids = sanan_story_point_cf_ids_for(issue&.project)
          sanan_values_for_cf_ids(issue, ids, preserve_order: true)
        end

        def sanan_values_for_cf_ids(issue, ids, preserve_order: false)
          return [] unless issue && ids.present?

          values = issue.visible_custom_field_values.select { |v| ids.include?(v.custom_field_id) }
          return values unless preserve_order

          by_id = values.index_by(&:custom_field_id)
          ids.filter_map { |id| by_id[id] }
        end

        def sanan_reject_grouped_cf_values(issue, values)
          ids = sanan_sprint_done_cf_ids_for(issue.project) + sanan_story_point_cf_ids_for(issue.project)
          return values if ids.empty?

          values.reject { |v| ids.include?(v.custom_field_id) }
        end

        def sanan_cf_value_present_for?(value)
          v = value.value
          if v.is_a?(Array)
            v.any? { |x| x.to_s.strip != '' }
          else
            v.to_s.strip != ''
          end
        end
      end
    end
  end
end

SananAgile::IssuesHelperPatch.apply!
