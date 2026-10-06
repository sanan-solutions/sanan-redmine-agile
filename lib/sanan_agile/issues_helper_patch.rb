# frozen_string_literal: true

require_dependency 'issues_helper'
require_dependency File.expand_path('agile_data_association', __dir__)

module SananAgile
  SP_FIBO = [0, 0.5, 1, 2, 3, 5, 8, 13, 21, 34].freeze

  module IssuesHelperPatch
    SPRINT_DONE_SETTING_KEYS = %w[
      done_be_cfid done_fe_cfid done_qa_cfid
      dod_cfid code_done_cfid uat_done_cfid
    ].freeze

    STORY_POINT_SETTING_KEYS = %w[
      size_be_cfid size_fe_cfid size_qa_cfid story_point_cfid
      sp_be_cfid sp_fe_cfid sp_qa_cfid sp_sprint_total_cfid
    ].freeze

    def self.apply!
      SananAgile::AgileDataAssociation.ensure! if defined?(SananAgile::AgileDataAssociation)

      # Redmine < 6 has no sprite_icon. redmineup prepends it onto ApplicationHelper,
      # but a helper reload leaves ActionView without the method (issue modal / checklists).
      if defined?(ActionView::Base) && !ActionView::Base.method_defined?(:sprite_icon)
        ActionView::Base.class_eval do
          def sprite_icon(_icon_name, label = '', icon_only: false, size: '18', css_class: nil, sprite: 'icons', plugin: nil, rtl: false)
            label.to_s.html_safe
          end
        end
      end
      if defined?(ApplicationHelper) && !ApplicationHelper.method_defined?(:sprite_icon)
        ApplicationHelper.class_eval do
          def sprite_icon(_icon_name, label = '', icon_only: false, size: '18', css_class: nil, sprite: 'icons', plugin: nil, rtl: false)
            label.to_s.html_safe
          end
        end
      end

      unless IssuesHelper.method_defined?(:sanan_issue_on_sprint?)
        IssuesHelper.module_eval do
          def sanan_issue_on_sprint?(issue, cfg = nil)
            return false unless issue

            cfg ||= SananAgile::ProjectSettings.load(issue.project_id) if issue.project_id
            return false unless cfg

            vid = issue.fixed_version_id.to_i
            vid.positive? && !SananAgile::ProductBacklog.version_ids(cfg).include?(vid)
          end
        end
      end

      unless IssuesHelper.method_defined?(:sanan_sprint_done_form_values_for)
        IssuesHelper.module_eval do
          def sanan_sprint_done_form_values_for(issue)
            ids = sanan_sprint_done_cf_ids_for(issue&.project)
            sp_ids = respond_to?(:sanan_story_point_cf_ids_for) ? sanan_story_point_cf_ids_for(issue&.project) : []
            return [] unless issue && ids.present?

            issue.editable_custom_field_values.select do |v|
              ids.include?(v.custom_field_id) && !sp_ids.include?(v.custom_field_id)
            end
          end
        end
      end

      unless IssuesHelper.method_defined?(:sanan_sp_fibo_select)
        IssuesHelper.module_eval do
          def sanan_sp_fibo_normalize(raw)
            return nil if raw.nil?

            s = raw.to_s.strip.tr(',', '.')
            return nil if s.empty?

            f = Float(s)
            (f % 1).zero? ? f.to_i : f
          rescue ArgumentError, TypeError
            nil
          end

          def sanan_sp_fibo_value_key(n)
            return '' if n.nil?

            f = n.to_f
            (f % 1).zero? ? f.to_i.to_s : f.to_s
          end

          def sanan_sp_fibo_options(current = nil)
            vals = SananAgile::SP_FIBO.dup
            cur = sanan_sp_fibo_normalize(current)
            if cur && vals.none? { |v| (v.to_f - cur.to_f).abs < 0.0001 }
              vals << cur
            end
            [['—', '']] + vals.map { |v| [sanan_sp_fibo_value_key(v), sanan_sp_fibo_value_key(v)] }
          end

          def sanan_sp_fibo_select(name, current, html_opts = {})
            selected = sanan_sp_fibo_value_key(sanan_sp_fibo_normalize(current))
            select_tag name, options_for_select(sanan_sp_fibo_options(current), selected), html_opts
          end
        end
      end

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
          ids.uniq - sanan_story_point_cf_ids_for(project)
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

        def sanan_sprint_done_form_values_for(issue)
          ids = sanan_sprint_done_cf_ids_for(issue&.project)
          return [] unless issue && ids.present?

          issue.editable_custom_field_values.select { |v| ids.include?(v.custom_field_id) }
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

        def sanan_cf_value_object_for(issue, cfid)
          return nil unless issue && cfid.to_i.positive?

          id = cfid.to_i
          (issue.custom_field_values + issue.visible_custom_field_values).find { |v| v.custom_field_id == id }
        end

        def sanan_format_sp(val)
          return '—' if val.nil?

          s = val.to_s.strip.tr(',', '.')
          return '—' if s.empty?

          f = Float(s)
          (f % 1).zero? ? f.to_i.to_s : format('%.2f', f).sub(/0+\z/, '').sub(/\.\z/, '')
        rescue ArgumentError, TypeError
          '—'
        end

        def sanan_sprint_team_total(issue, cfg)
          return 0.0 unless issue && cfg

          %w[sp_be_cfid sp_fe_cfid sp_qa_cfid].sum do |key|
            raw = issue.custom_field_value(cfg[key].to_i)
            s = raw.to_s.strip.tr(',', '.')
            s.empty? ? 0.0 : (Float(s) rescue 0.0)
          end
        end

        def sanan_issue_on_sprint?(issue, cfg = nil)
          return false unless issue

          cfg ||= SananAgile::ProjectSettings.load(issue.project_id) if issue.project_id
          return false unless cfg

          vid = issue.fixed_version_id.to_i
          vid.positive? && !SananAgile::ProductBacklog.version_ids(cfg).include?(vid)
        end
      end
    end
  end
end

SananAgile::IssuesHelperPatch.apply!
