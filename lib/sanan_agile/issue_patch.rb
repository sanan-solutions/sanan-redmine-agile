# frozen_string_literal: true
module SananAgile
  module IssuePatch
    def self.included(base)
      base.class_eval do
        # validate :sanan_require_done_parts_on_resolve, if: :will_check_resolve_rule?
        attr_accessor :_sanan_agile_internal
        # chạy sau khi issue lưu (insert/update)
        after_save :sanan_agile_after_save
      end
    end

    # Used by IssueQuery column `:sanan_release_version`
    def sanan_release_version
      ReleaseVersion.for_issue(self)
    end

    # “present?” cho CF, coi "0" cũng là có
    def cf_present?(cfid)
      id = cfid.to_i
      return false if id <= 0
      v = custom_field_value(id)
      if v.is_a?(Array)
        v.any? { |x| x.to_s.strip != '' }
      else
        v.to_s.strip != ''
      end
    end

    private

    def sanan_agile_after_save
      return if @_sanan_agile_internal
      return unless project.present?

      cfg = SananAgile::ProjectSettings.load(project.id)
      return if cfg.blank?

      return if cfg['sanan_agile_enabled'] == '0'

      # Lấy Version để ghi:
      # - Ưu tiên Default Version của project
      # - Nếu không có, fallback theo pick_version như Dev Done
      picked_version = pick_version(cfg) || project.default_version
      return unless picked_version

      begin
        self._sanan_agile_internal = true

        sync_story_points_from_cf(cfg)
        handle_dev_done(cfg, picked_version)
        handle_uat_done(cfg, picked_version)
        handle_code_done(cfg, picked_version)
      ensure
        self._sanan_agile_internal = false
      end
    end

    # ===== Story Point sync =====
    def sync_story_points_from_cf(cfg)
      cfid = cfg['story_point_cfid'].to_s.strip
      return if cfid.blank?

      raw = custom_field_value(cfid.to_i)
      sp  = parse_float_or_nil(raw)

      agile_model = defined?(SananAgile::AgileData) ? SananAgile::AgileData : AgileData
      row = agile_model.find_or_initialize_by(issue_id: id)
      return if row.persisted? && row.story_points == sp

      init_journal(User.current || User.anonymous,
                   "Sync SP CF(#{cfid}) → agile_data.story_points=#{sp.inspect}")
      row.story_points = sp
      row.save!(validate: false)
    end

    def will_check_resolve_rule?
      return false unless project_id

      cfg = SananAgile::ProjectSettings.load(project_id)
      @sanan_agile_cfg = cfg
      res_id = cfg['resolve_status'].to_i
      return false if res_id <= 0

      puts "testhahah: #{status_id.to_i} #{res_id}"

      # status đổi sang resolve?
      if respond_to?(:saved_change_to_status_id?)
        saved_change_to_status_id? && status_id.to_i == res_id
      else
        # Redmine < 4 fallback
        changes.key?('status_id') && status_id.to_i == res_id
      end
    end

    def sanan_require_done_parts_on_resolve()
      cfg = @sanan_agile_cfg || SananAgile::ProjectSettings.load(project_id)

      need_be = cf_present?(cfg['sp_be_cfid'])
      need_fe = cf_present?(cfg['sp_fe_cfid'])
      done_be = cf_present?(cfg['done_be_cfid'])
      done_fe = cf_present?(cfg['done_fe_cfid'])

      missing = []
      missing << l(:label_backend)  if need_be && !done_be
      missing << l(:label_frontend) if need_fe && !done_fe

      return if missing.empty?

      # Thông báo rõ ràng; Agile board sẽ hiển thị alert khi 422
      msg = "Không thể chuyển sang trạng thái Resolve: cần đánh dấu Done cho #{missing.join(' và ')}."
      errors.add(:base, msg)

      Rails.logger.warn "[sanan_agile] #{msg} (issue=#{id})"
      throw("SananAgileError: "+ msg) # ⬅️ dừng việc save
    end

    # ===== Done code in version =====
    def handle_code_done(cfg, picked_version)
      if will_check_resolve_rule?
        sanan_require_done_parts_on_resolve()
      end

      handle_change_status(cfg, picked_version, 'code_done_status_name', 'code_done_cfid')
    end

    # ===== Development Done =====
    def handle_dev_done(cfg, picked_version)
      handle_change_status(cfg, picked_version, 'development_done_status_name', 'development_done_cfid')
    end

    # ===== UAT Done =====
    def handle_uat_done(cfg, picked_version)
      handle_change_status(cfg, picked_version, 'uat_done_status_name', 'uat_done_cfid')
    end

    def handle_change_status(cfg, picked_version, status_key, cf_key)
      status_name  = cfg[status_key].to_s.strip
      cfid_s = cfg[cf_key].to_s.strip
      return if status_name.blank? || cfid_s.blank?
      return unless status&.name.to_s == status_name
      return unless saved_change_to_attribute?(:status_id)

      cfid = cfid_s.to_i
      val  = version_value_for_cf(cfid, picked_version)

      # init_journal(User.current || User.anonymous,
      #              "Auto set UAT Done → CF##{cfid}=#{val}")
      self.safe_attributes = { 'custom_field_values' => { cfid.to_s => val } }
      save(validate: false)
    end

    # ===== Helpers =====
    def version_value_for_cf(cfid, version)
      cf = IssueCustomField.find_by(id: cfid)
      return version.name.to_s unless cf && cf.field_format == 'version'
      version.id.to_s
    end

    def parse_float_or_nil(raw)
      return nil if raw.nil?
      s = raw.to_s.strip
      return nil if s.empty?
      s = s.tr(',', '.')
      Float(s) rescue nil
    end

    def pick_version(cfg)
      # Chiến lược chọn version cho Dev Done: default trước, fallback open mới nhất
      project.default_version ||
        project.versions.open.reorder(Arel.sql('effective_date NULLS LAST, id DESC')).first
    end
  end
end


unless Issue.included_modules.include?(SananAgile::IssuePatch)
  Issue.send(:include, SananAgile::IssuePatch)
end
