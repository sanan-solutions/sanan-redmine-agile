# frozen_string_literal: true
module SananAgile
  module VersionPicker
    module_function

    # Ưu tiên Default version của Redmine; nếu không có thì fallback theo strategy.
    def pick_for(project, cfg)
      return nil unless project

      # 1) Default version từ Redmine core
      default_ver =
        if project.respond_to?(:default_version)
          project.default_version
        elsif project.respond_to?(:default_version_id) && project.default_version_id.present?
          Version.find_by(id: project.default_version_id)
        end

      return default_ver if default_ver # dùng luôn (kể cả closed, theo yêu cầu)

      # 2) Fallback theo strategy
      opens = project.versions.where(status: 'open').to_a
      return nil if opens.empty?

      case (cfg['sanan_agile_version_strategy'] || 'nearest_due_date_or_latest_open')
      when 'latest_open_only'
        opens.max_by { |v| v.created_on || Time.at(0) }
      else
        today = Date.today
        with_due = opens.select { |v| v.due_date.present? }.sort_by(&:due_date)
        with_due.find { |v| v.due_date >= today } || opens.last
      end
    end
  end
end
