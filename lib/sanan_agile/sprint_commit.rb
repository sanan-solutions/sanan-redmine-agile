# frozen_string_literal: true

module SananAgile
  # Commit = standard tickets on the sprint version whose status is in set A
  # (`commit_dev_status_ids`). Empty set A = every ticket on the version (legacy).
  module SprintCommit
    module_function

    def enabled?(cfg)
      status_ids(cfg).any?
    end

    def status_ids(cfg)
      Array(cfg.to_h['commit_dev_status_ids']).map(&:to_i).reject(&:zero?).uniq
    end

    def in_dev?(issue, cfg)
      status_ids(cfg).include?(issue.status_id.to_i)
    end

    def issue_ids(version, cfg)
      return [] unless version

      cfg ||= ProjectSettings.load(version.project_id)
      rel = on_sprint_scope(version, cfg)
      rel = rel.where(status_id: status_ids(cfg)) if enabled?(cfg)
      rel.pluck(:id)
    end

    def committed?(issue, cfg)
      return false unless issue
      return false unless issue.fixed_version_id.to_i.positive?
      return false unless CommitLock.relevant_issue?(issue, cfg)
      return true unless enabled?(cfg)

      in_dev?(issue, cfg)
    end

    def on_sprint_scope(version, cfg)
      std = Array(cfg.to_h['standard_tracker']).map(&:to_i).reject(&:zero?)
      rel = Issue.where(project_id: version.project_id, fixed_version_id: version.id)
      rel = rel.where(tracker_id: std) if std.any?
      rel
    end
  end
end
