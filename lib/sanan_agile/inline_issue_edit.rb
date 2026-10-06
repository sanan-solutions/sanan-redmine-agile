# frozen_string_literal: true

require_dependency File.expand_path('issue_sp', __dir__)

module SananAgile
  # Inline editing of issue list cells (Issues tab). A field is a query column name: a core attribute
  # (status, assigned_to, due_date…) or a custom field (cf_12). Editing goes through Issue#safe_attributes,
  # so permissions, workflow transitions and read-only / disabled fields apply as in the issue form.
  module InlineIssueEdit
    # column name => [issue attribute, editor type]
    CORE = {
      'subject' => ['subject', 'text'],
      'tracker' => ['tracker_id', 'select'],
      'status' => ['status_id', 'select'],
      'priority' => ['priority_id', 'select'],
      'assigned_to' => ['assigned_to_id', 'select'],
      'category' => ['category_id', 'select'],
      'fixed_version' => ['fixed_version_id', 'select'],
      'start_date' => ['start_date', 'date'],
      'due_date' => ['due_date', 'date'],
      'done_ratio' => ['done_ratio', 'select'],
      'estimated_hours' => ['estimated_hours', 'number']
    }.freeze

    CF_FORMATS = {
      'string' => 'text', 'link' => 'text', 'int' => 'number', 'float' => 'number', 'date' => 'date',
      'list' => 'select', 'enumeration' => 'select', 'user' => 'select', 'version' => 'select', 'bool' => 'select'
    }.freeze

    BLANK_ALLOWED = %w[assigned_to category fixed_version start_date due_date estimated_hours].freeze

    # Story point fields: picked on the Fibonacci scale, as in the issue form.
    SP_SETTING_KEYS = SananAgile::IssueSp::KEYS.values.flat_map(&:values).freeze

    module_function

    def enabled?(cfg)
      cfg.to_h['sanan_agile_enabled'].to_s == '1' && cfg.to_h['issues_inline_edit_enabled'].to_s == '1'
    end

    def custom_field_for(issue, field)
      return nil unless field.to_s =~ /\Acf_(\d+)\z/

      id = Regexp.last_match(1).to_i
      issue.editable_custom_field_values.map(&:custom_field).detect { |cf| cf.id == id }
    end

    # nil when the user may not edit this field of this issue (or it is not supported).
    def editor(issue, field, user = User.current)
      return nil unless issue.attributes_editable?(user)

      if (cf = custom_field_for(issue, field))
        type = CF_FORMATS[cf.field_format]
        return nil if type.nil? || cf.multiple?

        value = issue.custom_field_value(cf)
        if story_point_field?(issue, cf)
          return { field: field, type: 'select', value: sp_value(value), options: fibo_options(value, cf),
                   allow_blank: !cf.is_required? }
        end

        {
          field: field, type: type, value: value.to_s,
          options: type == 'select' ? cf.possible_values_options(issue).map { |o| option(o) } : nil,
          allow_blank: !cf.is_required?
        }
      elsif (core = CORE[field.to_s])
        attribute, type = core
        return nil unless issue.safe_attribute?(attribute, user)

        {
          field: field, type: type, value: issue.send(attribute).to_s,
          options: type == 'select' ? core_options(issue, field, user) : nil,
          allow_blank: BLANK_ALLOWED.include?(field.to_s)
        }
      end
    end

    def story_point_field?(issue, cf)
      cfg = SananAgile::ProjectSettings.load(issue.project_id)
      SP_SETTING_KEYS.any? { |key| cfg[key].to_i == cf.id }
    end

    # "3.0" → "3" so the stored value matches a Fibonacci option.
    def sp_value(raw)
      s = raw.to_s.strip
      return '' if s.empty?

      n = Float(s.tr(',', '.'))
      n == n.to_i ? n.to_i.to_s : n.to_s
    rescue ArgumentError
      s
    end

    # Fibonacci scale; a stored value off the scale stays selectable so it is not lost by accident.
    def fibo_options(current, cf = nil)
      scale = SananAgile::SP_FIBO
      scale = scale.select { |v| v == v.to_i } if cf&.field_format == 'int' # 0.5 is not an integer
      values = scale.map { |v| v == v.to_i ? v.to_i.to_s : v.to_s }
      cur = sp_value(current)
      values << cur if cur.present? && !values.include?(cur)
      values.map { |v| [v, v] }
    end

    def option(raw)
      label, value = raw.is_a?(Array) ? raw : [raw, raw]
      [label.to_s, value.to_s]
    end

    def core_options(issue, field, user)
      case field.to_s
      when 'tracker' then issue.allowed_target_trackers(user).map { |t| [t.name, t.id.to_s] }
      when 'status' then issue.new_statuses_allowed_to(user).map { |s| [s.name, s.id.to_s] }
      when 'priority' then IssuePriority.active.map { |p| [p.name, p.id.to_s] }
      when 'assigned_to' then issue.assignable_users.map { |u| [u.name, u.id.to_s] }
      when 'category' then issue.project.issue_categories.map { |c| [c.name, c.id.to_s] }
      when 'fixed_version' then issue.assignable_versions.sort.map { |v| [v.to_s_with_project, v.id.to_s] }
      when 'done_ratio' then (0..10).map { |i| ["#{i * 10} %", (i * 10).to_s] }
      else []
      end
    end

    # Attributes hash for Issue#safe_attributes=.
    def attributes_for(issue, field, value)
      if (cf = custom_field_for(issue, field))
        { 'custom_field_values' => { cf.id.to_s => value.to_s } }
      elsif (core = CORE[field.to_s])
        { core.first => value.to_s }
      end
    end

    # Did the value stick? safe_attributes silently drops what the user may not set (e.g. a status the
    # workflow does not allow).
    def applied?(issue, field, value)
      if (cf = custom_field_for(issue, field))
        stored = issue.custom_field_value(cf).to_s
        return sp_value(stored) == sp_value(value) if story_point_field?(issue, cf)

        stored == value.to_s
      elsif (core = CORE[field.to_s])
        current = issue.send(core.first)
        return current.nil? if value.to_s.empty?

        case core.last
        when 'number' then current.to_f == value.to_s.tr(',', '.').to_f
        when 'date' then current.to_s == value.to_s
        else current.to_s == value.to_s
        end
      else
        false
      end
    end
  end
end
