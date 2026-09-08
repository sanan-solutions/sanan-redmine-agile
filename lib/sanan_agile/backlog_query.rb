# frozen_string_literal: true

module SananAgile
  class BacklogQuery
    Section = Struct.new(:key, :version, :active, :issues, :sp_total, keyword_init: true)

    def self.call(project, cfg: nil, filters: {})
      new(project, cfg: cfg, filters: filters).call
    end

    def initialize(project, cfg: nil, filters: {})
      @project = project
      @cfg = cfg || SananAgile::ProjectSettings.load(project.id)
      @filters = (filters || {}).with_indifferent_access
    end

    def call
      {
        active: active_section,
        future: future_sections,
        backlog: backlog_section,
        trackers: allowed_trackers,
        assignees: assignee_options,
        epics: epic_options,
        epic_stats: epic_stats
      }
    end

    def story_point_for(issue)
      cf = story_point_cfid
      return issue.agile_data&.story_points.to_f if cf <= 0

      cv = issue.custom_value_for(cf)
      parse_number(cv&.value)
    end

    private

    def active_section
      v = @project.default_version
      return nil unless v
      return nil if SananAgile::IntakeSource.intake_queue_version_ids(@cfg).include?(v.id)

      issues = issues_for_version(v.id)
      Section.new(key: "version-#{v.id}", version: v, active: true, issues: issues, sp_total: sum_sp(issues))
    end

    def future_sections
      default_id = @project.default_version&.id
      open_versions
        .reject { |v| default_id && v.id == default_id }
        .map do |v|
          issues = issues_for_version(v.id)
          Section.new(key: "version-#{v.id}", version: v, active: false, issues: issues, sp_total: sum_sp(issues))
        end
    end

    def backlog_section
      issues = filtered_scope.where(fixed_version_id: nil).to_a
      Section.new(key: 'backlog', version: nil, active: false, issues: issues, sp_total: sum_sp(issues))
    end

    def open_versions
      @open_versions ||= begin
        exclude_ids = SananAgile::IntakeSource.intake_queue_version_ids(@cfg)
        versions = @project.shared_versions.open.includes(:sanan_agile_version_meta).to_a
        versions.reject! { |v| exclude_ids.include?(v.id) } if exclude_ids.any?
        versions.sort_by { |v| [v.effective_date || Date.new(9999, 1, 1), v.id] }
      end
    end

    def issues_for_version(version_id)
      filtered_scope.where(fixed_version_id: version_id).to_a
    end

    def filtered_scope
      @filtered_scope ||= begin
        scope = Issue.visible
                     .where(project_id: @project.id)
                     .where(tracker_id: allowed_tracker_ids)
                     .joins(:priority)
                     .eager_load(:agile_data)
                     .includes(:tracker, :status, :priority, :assigned_to, :parent)
                     .order(Arel.sql(priority_order_sql))

        if hide_subtasks? && subtask_ids.any?
          scope = scope.where.not(tracker_id: subtask_ids)
        end

        if @filters[:tracker_id].present?
          scope = scope.where(tracker_id: @filters[:tracker_id].to_i)
        end

        if @filters[:assigned_to_id].present?
          if @filters[:assigned_to_id].to_s == '!*'
            scope = scope.where(assigned_to_id: nil)
          else
            scope = scope.where(assigned_to_id: @filters[:assigned_to_id].to_i)
          end
        end

        if @filters[:epic_id].present?
          scope = scope.where(parent_id: @filters[:epic_id].to_i)
        end

        if @filters[:q].present?
          raw = @filters[:q].to_s.strip
          q = "%#{raw.downcase}%"
          if raw =~ /\A\d+\z/
            scope = scope.where('LOWER(issues.subject) LIKE ? OR issues.id = ?', q, raw.to_i)
          else
            scope = scope.where('LOWER(issues.subject) LIKE ?', q)
          end
        end

        scope = apply_without_release_filter(scope) if without_release?

        scope
      end
    end

    def without_release?
      @filters[:without_release].to_s == '1'
    end

    # Match ReleaseVersion.for_issue: direct release_item, or standard child inheriting parent.
    def apply_without_release_filter(scope)
      attached_ids = ReleaseItem.joins(:issue)
                                .where(issues: { project_id: @project.id })
                                .pluck(:issue_id)
      scope = scope.where.not(id: attached_ids) if attached_ids.any?

      standard_ids = Array(@cfg['standard_tracker']).map(&:to_i).reject(&:zero?)
      if attached_ids.any? && standard_ids.any?
        scope = scope.where(
          'NOT (issues.tracker_id IN (?) AND issues.parent_id IN (?))',
          standard_ids,
          attached_ids
        )
      end
      scope
    end

    def allowed_tracker_ids
      @allowed_tracker_ids ||= begin
        ids = Array(@cfg['backlog_trackers']).map(&:to_i).reject(&:zero?)
        ids = Array(@cfg['standard_tracker']).map(&:to_i).reject(&:zero?) if ids.blank?
        ids
      end
    end

    def allowed_trackers
      Tracker.where(id: allowed_tracker_ids).order(:position)
    end

    def subtask_ids
      @subtask_ids ||= Array(@cfg['subtask_tracker']).map(&:to_i).reject(&:zero?)
    end

    def hide_subtasks?
      @cfg['backlog_hide_subtasks'].to_s != '0'
    end

    def story_point_cfid
      @cfg['story_point_cfid'].to_i
    end

    def sum_sp(issues)
      issues.sum { |i| story_point_for(i) }
    end

    def assignee_options
      ids = Issue.where(project_id: @project.id).where.not(assigned_to_id: nil).distinct.pluck(:assigned_to_id)
      return [] if ids.blank?

      User.where(id: ids).sort_by { |u| u.name.to_s.downcase }
    end

    def epic_options
      epic_id = @cfg['epic_tracker'].to_i
      return [] if epic_id <= 0

      Issue.where(project_id: @project.id, tracker_id: epic_id).order(:id)
    end

    # Per-epic child counts/progress (ignores epic_id filter so panel stays complete).
    # => { epic_id => { count:, closed:, progress: } }
    def epic_stats
      epic_tracker = @cfg['epic_tracker'].to_i
      return {} if epic_tracker <= 0 || allowed_tracker_ids.blank?

      scope = Issue.visible.where(project_id: @project.id, tracker_id: allowed_tracker_ids)
      scope = scope.where.not(tracker_id: subtask_ids) if hide_subtasks? && subtask_ids.any?
      scope = scope.where.not(parent_id: nil)

      totals = scope.group(:parent_id).count
      return {} if totals.empty?

      closed_status_ids = IssueStatus.where(is_closed: true).pluck(:id)
      closed = if closed_status_ids.any?
                 scope.where(status_id: closed_status_ids).group(:parent_id).count
               else
                 {}
               end
      totals.each_with_object({}) do |(parent_id, count), memo|
        total = count.to_i
        done = closed[parent_id].to_i
        memo[parent_id] = {
          count: total,
          closed: done,
          progress: total.positive? ? ((done.to_f / total) * 100).round : 0
        }
      end
    end

    def parse_number(v)
      return 0.0 if v.nil?

      s = v.to_s.strip.tr(',', '.').gsub(/[_\s]/, '')
      return 0.0 if s.empty?

      Float(s)
    rescue ArgumentError, TypeError
      0.0
    end

    # Highest urgency first (Immediate → … → Low), portable across inverted position setups.
    def priority_order_sql
      table = Enumeration.table_name
      <<~SQL.squish
        CASE COALESCE(#{table}.position_name, '')
          WHEN 'highest' THEN 1
          WHEN 'high2' THEN 2
          WHEN 'high3' THEN 3
          WHEN 'high' THEN 3
          WHEN 'default' THEN 4
          WHEN 'low2' THEN 5
          WHEN 'lowest' THEN 6
          ELSE 4
        END ASC,
        #{table}.position DESC,
        #{Issue.table_name}.id ASC
      SQL
    end
  end
end
