# frozen_string_literal: true
module SananAgile
  module IssuePatch
    def self.included(base)
      base.class_eval do
        # Block move to resolve_status unless required BE/FE Done flags are set.
        # Must be a real validation (not after_save + throw) so Agile board gets 422 JSON.
        validate :sanan_require_done_parts_on_resolve, if: :will_check_resolve_rule?
        attr_accessor :_sanan_agile_internal, :sanan_sp_size_attrs, :sanan_sp_sprint_attrs,
                      :sanan_skip_commit_lock
        validate :sanan_protect_commit_lock, if: :sanan_check_commit_lock?
        before_save :sanan_snapshot_sprint_sp_on_version_change
        # chạy sau khi issue lưu (insert/update)
        after_save :sanan_agile_after_save
        after_destroy :sanan_remove_roadmap_item
      end
    end

    def sanan_remove_roadmap_item
      SananRoadmapItem.where(issue_id: id).delete_all if defined?(SananRoadmapItem)
      SananRoadmapMove.where(issue_id: id).delete_all if defined?(SananRoadmapMove)
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

    def story_points
      val = nil
      if self.class.reflect_on_association(:agile_data)
        rec = if respond_to?(:agile_data_without_default)
                agile_data_without_default
              else
                association(:agile_data).load_target
              end
        val = rec.try(:story_points) if rec
      end
      if val.nil? && id && defined?(AgileData)
        val = AgileData.where(issue_id: id).pick(:story_points)
      end
      val
    end

    private

    def sanan_agile_after_save
      return if @_sanan_agile_internal
      return unless project.present?

      cfg = SananAgile::ProjectSettings.load(project.id)
      return if cfg.blank?

      return if cfg['sanan_agile_enabled'] == '0'

      begin
        self._sanan_agile_internal = true

        maybe_close_parent_epic!(cfg)
        persist_sanan_sp_size
        persist_sanan_sp_sprint

        # Lấy Version để ghi:
        # - Ưu tiên Default Version của project
        # - Nếu không có, fallback theo pick_version như Dev Done
        picked_version = pick_version(cfg) || project.default_version
        return unless picked_version

        sync_story_points_from_cf(cfg)
        handle_dev_done(cfg, picked_version)
        handle_uat_done(cfg, picked_version)
        handle_code_done(cfg, picked_version)
      ensure
        self._sanan_agile_internal = false
      end
    end

    # When all epic children (standard/backlog trackers) are closed → close epic.
    def maybe_close_parent_epic!(cfg)
      return unless status_id_just_changed?
      return unless status&.is_closed?

      epic = parent
      return unless epic

      epic_tracker = cfg['epic_tracker'].to_i
      return if epic_tracker <= 0
      return unless epic.tracker_id == epic_tracker
      return if epic.closed?

      children = epic_children_for_autoclose(epic, cfg)
      return if children.none?
      return if children.any? { |c| !c.closed? }

      closed_status = IssueStatus.where(is_closed: true).sorted.first ||
                      IssueStatus.where(is_closed: true).first
      return unless closed_status

      epic.init_journal(
        User.current || User.anonymous,
        '[sanan] Auto-close epic: all children closed'
      )
      epic.status = closed_status
      epic._sanan_agile_internal = true if epic.respond_to?(:_sanan_agile_internal=)
      unless epic.save
        Rails.logger.warn(
          "[sanan_agile] Failed to auto-close epic ##{epic.id}: #{epic.errors.full_messages.join(', ')}"
        )
      end
    ensure
      epic._sanan_agile_internal = false if epic && epic.respond_to?(:_sanan_agile_internal=)
    end

    def epic_children_for_autoclose(epic, cfg)
      scope = Issue.where(parent_id: epic.id, project_id: project.id)

      allowed = Array(cfg['backlog_trackers']).map(&:to_i).reject(&:zero?)
      allowed = Array(cfg['standard_tracker']).map(&:to_i).reject(&:zero?) if allowed.blank?
      scope = scope.where(tracker_id: allowed) if allowed.any?

      subtask_ids = Array(cfg['subtask_tracker']).map(&:to_i).reject(&:zero?)
      if cfg['backlog_hide_subtasks'].to_s != '0' && subtask_ids.any?
        scope = scope.where.not(tracker_id: subtask_ids)
      end

      scope.includes(:status).to_a
    end

    def status_id_just_changed?
      if respond_to?(:saved_change_to_status_id?)
        saved_change_to_status_id?
      else
        previous_changes.key?('status_id') || changes.key?('status_id')
      end
    end

    def sanan_snapshot_sprint_sp_on_version_change
      return if @_sanan_agile_internal
      return unless persisted?
      return unless project_id

      cfg = SananAgile::ProjectSettings.load(project_id)
      return if cfg.blank? || cfg['sanan_agile_enabled'] == '0'

      SananAgile::SprintSpHistory.on_version_change!(self, cfg)
    end

    def persist_sanan_sp_size
      return if sanan_sp_size_attrs.nil?

      SananAgile::SprintSpHistory.apply_size_attrs!(self, sanan_sp_size_attrs)
    end

    def persist_sanan_sp_sprint
      return if sanan_sp_sprint_attrs.nil?

      SananAgile::SprintSpHistory.apply_sprint_total_attrs!(self, sanan_sp_sprint_attrs)
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
      return false unless status_id.to_i == res_id

      # Pre-save change detection (validate runs before save)
      if respond_to?(:will_save_change_to_status_id?)
        will_save_change_to_status_id?
      elsif respond_to?(:status_id_changed?)
        status_id_changed?
      else
        changes.key?('status_id')
      end
    end

    def sanan_require_done_parts_on_resolve
      cfg = @sanan_agile_cfg || SananAgile::ProjectSettings.load(project_id)

      need_be = cf_present?(cfg['sp_be_cfid'])
      need_fe = cf_present?(cfg['sp_fe_cfid'])
      done_be = cf_present?(cfg['done_be_cfid'])
      done_fe = cf_present?(cfg['done_fe_cfid'])

      missing = []
      missing << 'BE done' if need_be && !done_be
      missing << 'FE done' if need_fe && !done_fe
      return if missing.empty?

      msg =
        if missing.length == 2
          'Không thể chuyển status: ticket này còn chưa đánh dấu BE done và FE done trên card (tick checkbox trước khi kéo).'
        elsif missing.first == 'BE done'
          'Không thể chuyển status: ticket này còn chưa đánh dấu BE done trên card (tick checkbox BE done trước khi kéo).'
        else
          'Không thể chuyển status: ticket này còn chưa đánh dấu FE done trên card (tick checkbox FE done trước khi kéo).'
        end
      errors.add(:base, msg)
      Rails.logger.warn "[sanan_agile] #{msg} (issue=#{id})"
    end

    # ===== Done code in version =====
    def handle_code_done(cfg, picked_version)
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

    def sanan_check_commit_lock?
      return false if sanan_skip_commit_lock
      return false if @_sanan_agile_internal
      return false unless project
      return false unless SananAgile::SprintSpHistory.version_changing?(self)

      true
    end

    def sanan_protect_commit_lock
      cfg = SananAgile::ProjectSettings.load(project.id)
      return if cfg['sanan_agile_enabled'].to_s != '1'
      return unless SananAgile::CommitLock.relevant_issue?(self, cfg)

      old_id = SananAgile::SprintSpHistory.previous_version_id(self)
      new_id = fixed_version_id
      return unless SananAgile::CommitLock.blocks_change?(project, old_id, new_id, cfg: cfg)

      errors.add(:base, I18n.t(:error_sanan_commit_locked))
    end
  end
end


unless Issue.included_modules.include?(SananAgile::IssuePatch)
  Issue.send(:include, SananAgile::IssuePatch)
end
