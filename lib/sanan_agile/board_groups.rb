# frozen_string_literal: true

module SananAgile
  # Agile board column groups (Development | UAT | Closed). Statuses are assigned to each group in the
  # settings; a status not assigned anywhere falls back to: closed status → Closed, otherwise Development.
  # UAT holds only the statuses picked for it (UAT statuses depend on each project's workflow).
  module BoardGroups
    GROUPS = %w[dev uat closed].freeze
    SETTING_KEYS = {
      'dev' => 'agile_board_group_dev_status_ids',
      'uat' => 'agile_board_group_uat_status_ids',
      'closed' => 'agile_board_group_closed_status_ids'
    }.freeze

    module_function

    def enabled?(cfg)
      cfg.to_h['sanan_agile_enabled'].to_s == '1' && cfg.to_h['agile_board_uat_group_enabled'].to_s == '1'
    end

    def configured_ids(cfg, group)
      Array(cfg.to_h[SETTING_KEYS.fetch(group)]).map(&:to_i).reject(&:zero?)
    end

    # { status_id => 'dev' | 'uat' | 'closed' } for every status. An explicit Closed choice wins, then UAT, then
    # Development (a status picked twice lands in the first of these).
    def status_groups(cfg, statuses = IssueStatus.all)
      explicit = {}
      %w[closed uat dev].each do |group|
        configured_ids(cfg, group).each { |id| explicit[id] ||= group }
      end
      statuses.each_with_object({}) do |status, map|
        map[status.id] = explicit[status.id] || (status.is_closed? ? 'closed' : 'dev')
      end
    end

    def status_ids_of(cfg, group)
      status_groups(cfg).select { |_id, g| g == group }.keys
    end
  end
end
