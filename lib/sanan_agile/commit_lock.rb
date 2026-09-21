# frozen_string_literal: true

require_dependency File.expand_path('product_backlog', __dir__)

module SananAgile
  # Q2d: last day to add/remove committed tickets is effective_date - N.
  # N = 0 or missing due date → no calendar lock.
  module CommitLock
    module_function

    def days(cfg)
      cfg.to_h['commit_lock_days_before_end'].to_i
    end

    def cutoff_on(version, cfg)
      n = days(cfg)
      due = version&.effective_date
      return nil if n <= 0 || due.blank?

      due - n
    end

    def locked?(version, cfg)
      return false unless version
      return false unless version.status.to_s == 'open'
      return false if excluded_version?(version, cfg)

      cut = cutoff_on(version, cfg)
      return false unless cut

      Date.current > cut
    end

    def excluded_version?(version, cfg)
      vid = version.id.to_i
      [
        ProductBacklog.version_id(cfg),
        cfg.to_h['cs_queue_version_id'].to_i,
        cfg.to_h['sale_queue_version_id'].to_i
      ].include?(vid)
    end

    def blocks_change?(project, old_version_id, new_version_id, cfg: nil)
      return false if old_version_id.to_i == new_version_id.to_i
      return false unless project

      cfg ||= ProjectSettings.load(project.id)
      [old_version_id, new_version_id].map(&:to_i).uniq.each do |vid|
        next unless vid.positive?

        version = project.shared_versions.find_by(id: vid)
        return true if version && locked?(version, cfg)
      end
      false
    end

    def relevant_issue?(issue, cfg)
      std = Array(cfg.to_h['standard_tracker']).map(&:to_i).reject(&:zero?)
      return true if std.blank?

      std.include?(issue.tracker_id.to_i)
    end
  end
end
