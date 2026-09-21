# frozen_string_literal: true

require_dependency File.expand_path('../product_backlog', __FILE__)

module SananAgile
  module SprintSpHistory
    module_function

    def on_version_change!(issue, cfg)
      return unless issue
      return unless version_changing?(issue)

      old_vid = previous_version_id(issue)
      snapshot!(issue, old_vid, cfg) if sprint_version?(old_vid, cfg)
      reset_sprint_team_cfs!(issue, cfg)
    end

    def snapshot!(issue, version_id, cfg, user = nil)
      return unless issue && issue.id && version_id.to_i.positive?

      row = SananIssueSprintSp.find_or_initialize_by(issue_id: issue.id, version_id: version_id.to_i)
      row.sp_be = db_cf_number(issue, cfg['sp_be_cfid'])
      row.sp_fe = db_cf_number(issue, cfg['sp_fe_cfid'])
      row.sp_qa = db_cf_number(issue, cfg['sp_qa_cfid'])
      if issue.respond_to?(:sanan_sp_sprint_attrs) && !issue.sanan_sp_sprint_attrs.nil?
        pending = params_hash(issue.sanan_sp_sprint_attrs)
        row.sp_total = blank_to_nil_decimal(pending[:sp_total])
      end
      row.captured_at = Time.current
      row.captured_by_id = (user || User.current).try(:id)
      row.save
    end

    def reset_sprint_team_cfs!(issue, cfg)
      values = {}
      %w[sp_be_cfid sp_fe_cfid sp_qa_cfid].each do |key|
        cfid = cfg[key].to_i
        next if cfid <= 0

        incoming = issue.custom_field_value(cfid).to_s.strip
        stored = db_cf_raw(issue, cfid).to_s.strip
        # Keep values the user typed this request for the new sprint.
        next if incoming.present? && incoming != stored

        values[cfid.to_s] = ''
      end
      issue.custom_field_values = values if values.any?
    end

    def apply_size_attrs!(issue, raw)
      return unless issue && issue.id && !raw.nil?

      h = params_hash(raw)
      row = SananIssueSpSize.find_or_initialize_by(issue_id: issue.id)
      row.sp_be = blank_to_nil_decimal(h[:sp_be])
      row.sp_fe = blank_to_nil_decimal(h[:sp_fe])
      row.sp_qa = blank_to_nil_decimal(h[:sp_qa])
      row.save
    end

    def apply_sprint_total_attrs!(issue, raw)
      return unless issue && issue.id && !raw.nil?
      return if version_just_changed?(issue)

      cfg = SananAgile::ProjectSettings.load(issue.project_id)
      return unless cfg.present? && sprint_version?(issue.fixed_version_id, cfg)

      h = params_hash(raw)
      row = SananIssueSprintSp.find_or_initialize_by(
        issue_id: issue.id,
        version_id: issue.fixed_version_id.to_i
      )
      row.sp_total = blank_to_nil_decimal(h[:sp_total])
      row.captured_at ||= Time.current
      row.save
    end

    def sprint_version?(version_id, cfg)
      vid = version_id.to_i
      return false unless vid.positive?
      return false if ProductBacklog.version_ids(cfg).include?(vid)

      true
    end

    def db_cf_number(issue, cfid)
      blank_to_nil_decimal(db_cf_raw(issue, cfid))
    end

    def db_cf_raw(issue, cfid)
      id = cfid.to_i
      return nil if id <= 0 || issue.id.nil?

      CustomValue.where(
        customized_type: 'Issue',
        customized_id: issue.id,
        custom_field_id: id
      ).pick(:value)
    end

    def blank_to_nil_decimal(raw)
      s = raw.to_s.strip.tr(',', '.')
      return nil if s.empty?

      Float(s)
    rescue ArgumentError, TypeError
      nil
    end

    def params_hash(raw)
      h = if raw.respond_to?(:to_unsafe_h)
            raw.to_unsafe_h
          elsif raw.respond_to?(:to_h)
            raw.to_h
          else
            {}
          end
      h.with_indifferent_access
    end

    def version_just_changed?(issue)
      if issue.respond_to?(:saved_change_to_fixed_version_id?)
        issue.saved_change_to_fixed_version_id?
      elsif issue.respond_to?(:previous_changes)
        issue.previous_changes.key?('fixed_version_id')
      else
        false
      end
    end

    def version_changing?(issue)
      if issue.respond_to?(:will_save_change_to_fixed_version_id?)
        issue.will_save_change_to_fixed_version_id?
      elsif issue.respond_to?(:fixed_version_id_changed?)
        issue.fixed_version_id_changed?
      else
        issue.changes.key?('fixed_version_id')
      end
    end

    def previous_version_id(issue)
      if issue.respond_to?(:fixed_version_id_in_database)
        issue.fixed_version_id_in_database
      elsif issue.respond_to?(:fixed_version_id_was)
        issue.fixed_version_id_was
      else
        issue.changes['fixed_version_id']&.first
      end
    end
  end
end
