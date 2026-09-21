# frozen_string_literal: true

module SananAgile
  # Product Backlog storage:
  # - If settings[backlog_version_id] is set → issues on that Version
  # - Otherwise → issues with fixed_version_id = nil
  module ProductBacklog
    module_function

    def version_id(cfg)
      cfg.to_h['backlog_version_id'].to_i
    end

    def configured?(cfg)
      version_id(cfg).positive?
    end

    def version(project, cfg)
      vid = version_id(cfg)
      return nil unless vid.positive?

      project.shared_versions.find_by(id: vid)
    end

    def version_ids(cfg)
      vid = version_id(cfg)
      vid.positive? ? [vid] : []
    end

    # Apply Product Backlog target onto an issue (does not save).
    def assign!(issue, project, cfg)
      v = version(project, cfg)
      issue.fixed_version = v # nil when unset → unscheduled bucket
      v
    end

    def scope(relation, cfg)
      vid = version_id(cfg)
      if vid.positive?
        relation.where(fixed_version_id: vid)
      else
        relation.where(fixed_version_id: nil)
      end
    end

    def issue_in_backlog?(issue, cfg)
      vid = version_id(cfg)
      if vid.positive?
        issue.fixed_version_id.to_i == vid
      else
        issue.fixed_version_id.nil?
      end
    end
  end
end
