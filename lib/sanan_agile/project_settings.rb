# frozen_string_literal: true
require_dependency File.expand_path('done_in_sprint', __dir__)

module SananAgile
  class ProjectSettings
    DEFAULTS = {
      'sanan_agile_enabled'             => '0',
      'sanan_agile_version_strategy'            => 'nearest_due_date_or_latest_open', # fallback khi KHÔNG có default version
      'skip_if_already_set' => '1',

      'card_color_tracker_map'=> {},
      'card_color_tracker_mode' => 'border',
      # Auto set story point for redmine agile
      # Size (estimate of the whole ticket, does not change per sprint): issue custom fields
      'story_point_cfid'    => '',        # Size Total
      'size_be_cfid'        => '',
      'size_fe_cfid'        => '',
      'size_qa_cfid'        => '',
      # "This sprint" SP (current / next sprint; snapshot per sprint in sanan_issue_sprint_sps):
      # sp_be_cfid / sp_fe_cfid / sp_qa_cfid below, and the sprint Total (also a sub-task's personal SP)
      'sp_sprint_total_cfid' => '',
      'sp_total_formula'    => 'manual',  # manual | max | avg
      'sp_total_require_qa' => '0',       # Total empty unless tester SP is set

      # auto set version by status
      'code_done_status_name'        => '',  # tên status “Done code in version”
      'code_done_cfid'               => '',   # CF để ghi version khi đạt trạng thái này


      'uat_done_status_name' => '',   # tên status dùng làm cột/trigger “UAT Done”
      'uat_done_cfid'        => '',    # Issue CF sẽ ghi Default Version khi tới UAT Done

      'dod_checkbox_trackers'        => [],  # array các tracker id
      'dod_checkbox_statuses'    => [],   # [status_id,...]  <<-- NEW
      'dod_cfid'                     => '',   # CF cho DoD in Sprint

      # CF ids
      'sp_qa_cfid'            =>'',
      'sp_be_cfid'            => '',  # Story point Backend
      'sp_fe_cfid'            => '',  # Story point Frontend
      'done_be_cfid'          => '',  # Done Backend In Sprint
      'done_fe_cfid'          => '',  # Done Frontend In Sprint
      'done_qa_cfid'          => '',  # Done QA In Sprint
      # Trigger status (name) filling each Done field automatically; blank = card checkbox / manual only
      'done_be_status_name'   => '',
      'done_fe_status_name'   => '',
      'done_qa_status_name'   => '',

      # show checkboxes only for these trackers (optional)
      'befe_trackers'         => [],  # [tracker_id,...] (để trống = tất cả)
      'befe_statuses'  => [],
      'resolve_status'  => '',
      # auto move khi đủ điều kiện
      'auto_move_enabled'     => '0',
      'auto_move_status_id'   => '',  # issue status id đích

      # version attribute — actual (snapshot on close)
      'sp_actual_version_cfid'=>'',
      'sp_be_actual_version_cfid'=>'',
      'sp_fe_actual_version_cfid'=>'',
      'sp_qa_actual_version_cfid'=>'',

      # version attribute — commit (snapshot on close)
      'sp_commit_version_cfid'=>'',
      'sp_be_commit_version_cfid'=>'',
      'sp_fe_commit_version_cfid'=>'',
      'sp_qa_commit_version_cfid'=>'',

      'test_level_cfid' =>'',

      'release_status_filter_ids' => [],       # danh sách status id hiển thị trong modal pick issue
      'epic_tracker' => '',
      'standard_tracker' => [],
      'subtask_tracker' => [],
      'release_add_child_issue_standard_tracker' => '0',
      'release_released_status_id'=> '',
      'release_close_status_id'=> '',

      # Backlog
      'backlog_enabled' => '0',
      'backlog_trackers' => [],   # empty = use standard_tracker
      'backlog_hide_subtasks' => '1',
      # Optional Version used as Product Backlog bucket; blank = fixed_version_id nil
      'backlog_version_id' => '',
      'velocity_window' => '3',
      # Last day to add/remove committed tickets = due - N. 0 = no calendar lock.
      'commit_lock_days_before_end' => '0',

      # Agile board: hide these trackers from cards/column counts (e.g. Epic)
      'agile_board_hidden_tracker_ids' => [],
      # Agile board backlog panel (drag tickets between the backlog and the board's sprint)
      'agile_board_backlog_enabled' => '0',
      # Issues tab: edit list cells in place
      'issues_inline_edit_enabled' => '1',
      # Agile board column groups: Development | UAT | Closed (statuses per group below), each collapsible
      'agile_board_uat_group_enabled' => '0',
      # Statuses per column group (not picked anywhere: closed → Closed, otherwise Development)
      'agile_board_group_dev_status_ids' => [],
      'agile_board_group_uat_status_ids' => [],
      'agile_board_group_closed_status_ids' => [],
      # Statuses left out of Roadmap progress (scope removed, e.g. Rejected)
      'progress_excluded_status_ids' => [],

      # Product roadmap (quarterly Epic plan)
      'roadmap_enabled' => '0',
      'roadmap_status_colors' => {},   # { status_id => '#RRGGBB' }
      'roadmap_capacity_window' => '5', # closed sprints averaged for team effort/capacity (3 | 5)
      'roadmap_blocked_status_ids' => [], # Story statuses counted as Blocked (empty = status name contains "block")

      # CS / Sale intake backlogs
      'cs_backlog_enabled' => '0',
      'sale_backlog_enabled' => '0',
      'cs_queue_version_id' => '',
      'sale_queue_version_id' => '',
      'intake_source_cfid' => '',           # Issue CF list: product|cs|sale (or labels)
      'cs_ready_status_ids' => [],
      'sale_ready_status_ids' => [],
      'default_cs_quota_sp' => '10',
      'default_sale_quota_sp' => '8',
      'allow_quota_override' => '0',
      'intake_ready_sla_days' => '3',
      'cs_ready_sp_alert_threshold' => '20',
      'sale_ready_sp_alert_threshold' => '15',
      'intake_ready_sp_alert_mail' => '0',
      # Date/DateTime CF: promised deadline with customer (CS/Sale)
      'customer_deadline_cfid' => ''
    }.freeze

    PLUGIN_KEY = :sanan_redmine_agile

    # Plugin-wide defaults live under this key of the store, next to the per-project hashes. A project stores
    # only what differs from them, so changing a global setting reaches every project that follows it.
    GLOBAL_KEY = '_global'

    # Settings that only make sense per project (they point at the project's own versions, or switch the
    # plugin on): never taken from, nor shown in, the global settings.
    PROJECT_ONLY_KEYS = %w[sanan_agile_enabled backlog_version_id cs_queue_version_id sale_queue_version_id].freeze

    def self.store
      Setting.send(:"plugin_#{PLUGIN_KEY}") || {}
    end

    # Global settings over the built-in defaults.
    def self.load_global
      SananAgile::DoneInSprint.migrate_legacy!(DEFAULTS.merge(global_overrides))
    end

    def self.global_overrides
      (store[GLOBAL_KEY] || {}).except(*PROJECT_ONLY_KEYS)
    end

    def self.load(project_id)
      project = store[project_id.to_s] || {}
      SananAgile::DoneInSprint.migrate_legacy!(DEFAULTS.merge(global_overrides).merge(project))
    end

    # Keys a project takes from the global settings (not stored for the project).
    def self.inherited_keys(project_id)
      stored = store[project_id.to_s] || {}
      DEFAULTS.keys - PROJECT_ONLY_KEYS - stored.keys
    end

    def self.save(project_id, params_hash)
      cfg = DEFAULTS.merge(params_hash.to_h.stringify_keys.slice(*DEFAULTS.keys))
      global = load_global
      overrides = cfg.reject do |key, value|
        !PROJECT_ONLY_KEYS.include?(key) && comparable(value) == comparable(global[key])
      end
      write(project_id.to_s, overrides)
    end

    def self.save_global(params_hash)
      cfg = DEFAULTS.merge(params_hash.to_h.stringify_keys.slice(*DEFAULTS.keys)).except(*PROJECT_ONLY_KEYS)
      write(GLOBAL_KEY, cfg)
    end

    def self.write(key, value)
      data = store.dup
      # Own copies: values shared with DEFAULTS or another entry would be dumped as YAML aliases.
      data[key] = JSON.parse(value.to_json)
      Setting.send(:"plugin_#{PLUGIN_KEY}=", data)
    end

    # Values as the form submits them: multi-selects carry a blank entry and keep no order.
    def self.comparable(value)
      case value
      when Array then value.map(&:to_s).reject(&:empty?).sort
      when Hash then value.to_h.transform_keys(&:to_s).transform_values(&:to_s).reject { |_k, v| v.empty? }.sort.to_h
      else value.to_s
      end
    end
  end
end
