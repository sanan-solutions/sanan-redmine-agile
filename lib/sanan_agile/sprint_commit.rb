# frozen_string_literal: true

module SananAgile
  # Sprint commit = standard tickets on the sprint version with a "This sprint" SP for at least one part
  # (BE / FE / QA team SP, or the sprint Total). A ticket can commit fully (dev + test) or only some
  # parts (only BE, only FE, only test…); its status does not matter, so a ticket stays committed after
  # its dev part is done and it moves on to UAT / Done. The commit set may change during the sprint.
  #
  # Without team SP fields configured there is no commit selection: every standard ticket on the sprint counts.
  module SprintCommit
    TEAM_SP_KEYS = %w[sp_be_cfid sp_fe_cfid sp_qa_cfid].freeze

    module_function

    # Commit tracking (board tags, commit report) needs the team "This sprint" SP fields.
    def enabled?(cfg)
      sp_based?(cfg)
    end

    # Commit decided by "This sprint" SP (team SP fields configured).
    def sp_based?(cfg)
      team_cfids(cfg).any?
    end

    def team_cfids(cfg)
      TEAM_SP_KEYS.map { |k| cfg.to_h[k].to_i }.select(&:positive?)
    end

    def issue_ids(version, cfg)
      return [] unless version

      cfg ||= ProjectSettings.load(version.project_id)
      rel = on_sprint_scope(version, cfg)
      return with_sprint_sp(rel.pluck(:id), version.id, cfg) if sp_based?(cfg)

      rel.pluck(:id)
    end

    def committed?(issue, cfg)
      return false unless issue
      return false unless issue.fixed_version_id.to_i.positive?
      return false unless CommitLock.relevant_issue?(issue, cfg)
      return with_sprint_sp([issue.id], issue.fixed_version_id, cfg).any? if sp_based?(cfg)

      true
    end

    # Ids of the given issues that are committed in their current sprint (one query per sprint).
    def committed_ids_among(issues, cfg)
      relevant = Array(issues).select do |i|
        i.fixed_version_id.to_i.positive? && CommitLock.relevant_issue?(i, cfg)
      end
      return relevant.select { |i| committed?(i, cfg) }.map(&:id) unless sp_based?(cfg)

      relevant.group_by(&:fixed_version_id).flat_map do |vid, list|
        with_sprint_sp(list.map(&:id), vid, cfg)
      end
    end

    # Subset of ids having a "This sprint" SP on version_id: a team SP value, or a sprint Total.
    def with_sprint_sp(ids, version_id, cfg)
      ids = Array(ids).map(&:to_i)
      return [] if ids.empty?

      found = CustomValue.where(customized_type: 'Issue', custom_field_id: team_cfids(cfg), customized_id: ids)
                         .where.not(value: [nil, ''])
                         .distinct.pluck(:customized_id)
      if defined?(SananIssueSprintSp)
        found |= SananIssueSprintSp.where(version_id: version_id.to_i, issue_id: ids)
                                   .where.not(sp_total: nil).pluck(:issue_id)
      end
      found = found.to_set
      ids.select { |id| found.include?(id) }
    end

    def on_sprint_scope(version, cfg)
      std = Array(cfg.to_h['standard_tracker']).map(&:to_i).reject(&:zero?)
      rel = Issue.where(project_id: version.project_id, fixed_version_id: version.id)
      rel = rel.where(tracker_id: std) if std.any?
      rel
    end
  end
end
