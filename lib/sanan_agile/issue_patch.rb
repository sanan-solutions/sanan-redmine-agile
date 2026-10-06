# frozen_string_literal: true
module SananAgile
  module IssuePatch
    def self.included(base)
      base.class_eval do
        # Block move to resolve_status unless required BE/FE Done flags are set.
        # Must be a real validation (not after_save + throw) so Agile board gets 422 JSON.
        validate :sanan_require_done_parts_on_resolve, if: :will_check_resolve_rule?
        attr_accessor :_sanan_agile_internal, :sanan_skip_commit_lock
        validate :sanan_protect_commit_lock, if: :sanan_check_commit_lock?
        before_save :sanan_snapshot_sprint_sp_on_version_change
        before_save :sanan_apply_sp_totals
        before_save :sanan_stamp_done_in_sprint
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

    # SP shown by redmine_agile (cards, column sums): the "This sprint" Total (SananAgile::IssueSp).
    def story_points
      return nil unless project_id

      cfg = SananAgile::ProjectSettings.load(project_id)
      SananAgile::IssueSp.total_of(SananAgile::IssueSp.values(self, cfg, :sprint), cfg)
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

    # Size / Sprint Totals from their BE / FE / QA parts (formula in the settings), on every save.
    def sanan_apply_sp_totals
      return if @_sanan_agile_internal
      return unless project_id

      cfg = SananAgile::ProjectSettings.load(project_id)
      return if cfg.blank? || cfg['sanan_agile_enabled'] == '0'

      SananAgile::SpTotalFormula.apply_issue!(self, cfg)
    end

    # Done BE / FE / Code / QA, UAT Done: filled in the same save when the ticket enters their status.
    def sanan_stamp_done_in_sprint
      return if @_sanan_agile_internal
      return unless project_id
      return unless new_record? || will_save_change_to_status_id?

      cfg = SananAgile::ProjectSettings.load(project_id)
      return if cfg.blank? || cfg['sanan_agile_enabled'] == '0'

      SananAgile::DoneInSprint.stamp!(self, cfg)
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

    # ===== Helpers =====
    def parse_float_or_nil(raw)
      return nil if raw.nil?
      s = raw.to_s.strip
      return nil if s.empty?
      s = s.tr(',', '.')
      Float(s) rescue nil
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
