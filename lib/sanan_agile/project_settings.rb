# frozen_string_literal: true
module SananAgile
  class ProjectSettings
    DEFAULTS = {
      'sanan_agile_enabled'             => '0',
      'sanan_agile_version_strategy'            => 'nearest_due_date_or_latest_open', # fallback khi KHÔNG có default version
      'skip_if_already_set' => '1',

      # Auto set story point for redmine agile
      'story_point_cfid'    => '',

      # auto set version by status
      'code_done_status_name'        => '',  # tên status “Done code in version”
      'code_done_cfid'               => '',   # CF để ghi version khi đạt trạng thái này

      'development_done_status_name' => '',
      'development_done_cfid' => '',

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

      # show checkboxes only for these trackers (optional)
      'befe_trackers'         => [],  # [tracker_id,...] (để trống = tất cả)
      'befe_statuses'  => [],
      'resolve_status'  => '',
      # auto move khi đủ điều kiện
      'auto_move_enabled'     => '0',
      'auto_move_status_id'   => '',  # issue status id đích

      # version attribute
      'sp_actual_version_cfid'=>'',
      'sp_be_actual_version_cfid'=>'',
      'sp_fe_actual_version_cfid'=>'',
      'sp_qa_actual_version_cfid'=>'',
    }.freeze

    PLUGIN_KEY = :sanan_redmine_agile

    def self.load(project_id)
      store = Setting.send(:"plugin_#{PLUGIN_KEY}") || {}
      DEFAULTS.merge(store[project_id.to_s] || {})
    end

    def self.save(project_id, params_hash)
      store = Setting.send(:"plugin_#{PLUGIN_KEY}") || {}
      cfg   = DEFAULTS.merge(params_hash.to_h.slice(*DEFAULTS.keys))
      store[project_id.to_s] = cfg
      Setting.send(:"plugin_#{PLUGIN_KEY}=", store)
    end
  end
end
