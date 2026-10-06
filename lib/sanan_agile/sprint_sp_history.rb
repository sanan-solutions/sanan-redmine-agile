# frozen_string_literal: true

require_dependency File.expand_path('../product_backlog', __FILE__)

module SananAgile
  module SprintSpHistory
    module_function

    # Leaving a sprint: snapshot its "This sprint" SP (BE / FE / QA / Total) into the history and clear the
    # fields for the next estimate. Moving from the Product Backlog (or no version) into a sprint keeps the
    # values: they are the re-estimate made for that sprint.
    def on_version_change!(issue, cfg)
      return unless issue
      return unless version_changing?(issue)

      old_vid = previous_version_id(issue)
      return unless sprint_version?(old_vid, cfg)

      snapshot!(issue, old_vid, cfg)
      reset_sprint_cfs!(issue, cfg)
    end

    def snapshot!(issue, version_id, cfg, user = nil)
      return unless issue && issue.id && version_id.to_i.positive?

      row = SananIssueSprintSp.find_or_initialize_by(issue_id: issue.id, version_id: version_id.to_i)
      row.sp_be = db_cf_number(issue, cfg['sp_be_cfid'])
      row.sp_fe = db_cf_number(issue, cfg['sp_fe_cfid'])
      row.sp_qa = db_cf_number(issue, cfg['sp_qa_cfid'])
      row.sp_total = db_cf_number(issue, cfg['sp_sprint_total_cfid'])
      row.captured_at = Time.current
      row.captured_by_id = (user || User.current).try(:id)
      row.save
    end

    def reset_sprint_cfs!(issue, cfg)
      values = {}
      SananAgile::IssueSp::KEYS[:sprint].each_value do |key|
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

    # A real sprint: not the Product Backlog nor a CS / Sale intake queue.
    def sprint_version?(version_id, cfg)
      vid = version_id.to_i
      return false unless vid.positive?

      !(ProductBacklog.version_ids(cfg) + SananAgile::IntakeSource.intake_queue_version_ids(cfg)).include?(vid)
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
