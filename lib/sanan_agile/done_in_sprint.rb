# frozen_string_literal: true

module SananAgile
  # "Done in sprint" milestones. Each one is an issue field holding the sprint a part of the ticket was
  # done in, filled by a card checkbox (BE / FE / DoD) and/or automatically when the ticket enters a
  # trigger status. All of them are configured in one place: Settings → Workflow → Done in Sprint.
  module DoneInSprint
    # milestone => [field setting, trigger status setting]
    MILESTONES = {
      'be' => %w[done_be_cfid done_be_status_name],
      'fe' => %w[done_fe_cfid done_fe_status_name],
      'code' => %w[code_done_cfid code_done_status_name],
      'qa' => %w[done_qa_cfid done_qa_status_name],
      'uat' => %w[uat_done_cfid uat_done_status_name]
    }.freeze

    # Done QA used to be set twice: a field in the BE / FE / QA tab, and Workflow → "Development / QA
    # Done" (trigger status + field). Older settings are folded into Done QA.
    LEGACY_QA_CFID = 'development_done_cfid'
    LEGACY_QA_STATUS = 'development_done_status_name'

    module_function

    def migrate_legacy!(cfg)
      legacy_cfid = cfg.delete(LEGACY_QA_CFID).to_s.strip
      legacy_status = cfg.delete(LEGACY_QA_STATUS).to_s.strip
      cfg['done_qa_cfid'] = legacy_cfid if cfg['done_qa_cfid'].to_s.strip.empty? && legacy_cfid.present?
      cfg['done_qa_status_name'] = legacy_status if cfg['done_qa_status_name'].to_s.strip.empty? && legacy_status.present?
      cfg
    end

    # Sprint a part done now belongs to: the ticket's own sprint, else the default / nearest open version
    # (ticket still in the Product Backlog or an intake queue).
    def version_for(issue, cfg)
      version = issue.fixed_version
      return version if version && !non_sprint_version_ids(cfg).include?(version.id)

      project = issue.project
      return nil unless project

      project.default_version ||
        project.versions.open.reorder(Arel.sql('effective_date IS NULL, effective_date ASC, id DESC')).first
    end

    def non_sprint_version_ids(cfg)
      %w[backlog_version_id cs_queue_version_id sale_queue_version_id].map { |k| cfg.to_h[k].to_i }.select(&:positive?)
    end

    def value_for(cfid, version)
      cf = IssueCustomField.find_by(id: cfid)
      cf&.field_format == 'version' ? version.id.to_s : version.name.to_s
    end

    # Before save: fill every milestone whose trigger status the ticket is entering. Values are assigned
    # in memory, so they are saved (and journaled) with the ticket — no second save.
    def stamp!(issue, cfg)
      status_name = issue.status&.name.to_s
      return if status_name.empty?

      cfids = MILESTONES.values.filter_map do |cf_key, status_key|
        next unless cfg[status_key].to_s.strip == status_name

        cfid = cfg[cf_key].to_i
        cfid if cfid.positive?
      end
      available = issue.available_custom_fields.map(&:id)
      cfids &= available
      return if cfids.empty?

      version = version_for(issue, cfg)
      return unless version

      issue.custom_field_values = cfids.to_h { |cfid| [cfid.to_s, value_for(cfid, version)] }
    end
  end
end
