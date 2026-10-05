# frozen_string_literal: true

module SananAgile
  class BacklogQuery
    BACKLOG_PAGE_SIZE = 50

    Section = Struct.new(
      :key, :version, :active, :issues, :sp_total,
      :issue_count, :has_more, :next_offset,
      :sp_be, :sp_fe, :sp_qa,
      keyword_init: true
    )

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

    def backlog_page(offset: 0, limit: BACKLOG_PAGE_SIZE, compute_sp: true)
      offset = [offset.to_i, 0].max
      limit = [[limit.to_i, 1].max, 100].min
      scope = backlog_issues_scope
      total = count_scope(scope)
      issues = scope.offset(offset).limit(limit).to_a
      loaded = offset + issues.size
      ids = compute_sp ? scope.except(:includes, :eager_load, :preload, :order).distinct.pluck(:id) : []
      {
        issues: issues,
        total: total,
        loaded: loaded,
        has_more: loaded < total,
        next_offset: loaded,
        sp_total: compute_sp ? sum_sp_ids(ids) : nil,
        sp_be: compute_sp ? sum_cf_ids(ids, 'sp_be_cfid') : nil,
        sp_fe: compute_sp ? sum_cf_ids(ids, 'sp_fe_cfid') : nil,
        sp_qa: compute_sp ? sum_cf_ids(ids, 'sp_qa_cfid') : nil
      }
    end


    # Open tickets of the Product Backlog (version_id nil) or of a sprint, with the backlog filters applied.
    def open_issues_scope(version_id = nil)
      scope = version_id ? filtered_scope.where(fixed_version_id: version_id) : backlog_issues_scope
      scope.where(status_id: IssueStatus.where(is_closed: false).select(:id))
    end

    private

    def active_section
      v = @project.default_version
      return nil unless v
      return nil if excluded_version_ids.include?(v.id)

      issues = issues_for_version(v.id)
      sprint_section("version-#{v.id}", v, true, issues)
    end

    def future_sections
      default_id = @project.default_version&.id
      open_versions
        .reject { |v| default_id && v.id == default_id }
        .map do |v|
          issues = issues_for_version(v.id)
          sprint_section("version-#{v.id}", v, false, issues)
        end
    end

    def sprint_section(key, version, active, issues)
      ids = issues.map(&:id)
      if version && SananAgile::SprintCommit.enabled?(@cfg)
        ids = SananAgile::SprintCommit.issue_ids(version, @cfg)
      end
      Section.new(
        key: key,
        version: version,
        active: active,
        issues: issues,
        sp_total: sum_sp_ids(ids),
        issue_count: issues.size,
        has_more: false,
        next_offset: issues.size,
        sp_be: sum_cf_ids(ids, 'sp_be_cfid'),
        sp_fe: sum_cf_ids(ids, 'sp_fe_cfid'),
        sp_qa: sum_cf_ids(ids, 'sp_qa_cfid')
      )
    end

    def backlog_section
      page = backlog_page(offset: 0)
      Section.new(
        key: 'backlog',
        version: nil,
        active: false,
        issues: page[:issues],
        sp_total: page[:sp_total],
        issue_count: page[:total],
        has_more: page[:has_more],
        next_offset: page[:next_offset],
        sp_be: page[:sp_be],
        sp_fe: page[:sp_fe],
        sp_qa: page[:sp_qa]
      )
    end

    def backlog_issues_scope
      SananAgile::ProductBacklog.scope(filtered_scope, @cfg)
    end

    def count_scope(scope)
      scope.except(:includes, :eager_load, :preload, :order).distinct.count('issues.id')
    end

    def sum_sp_ids(ids)
      return 0.0 if ids.blank?

      cf = story_point_cfid
      if cf <= 0
        defined?(AgileData) ? AgileData.where(issue_id: ids).sum(:story_points).to_f : 0.0
      else
        sum_custom_values(ids, cf)
      end
    end

    def sum_cf_ids(ids, setting_key)
      cf = @cfg[setting_key].to_i
      return nil unless cf.positive?
      return 0.0 if ids.blank?

      sum_custom_values(ids, cf)
    end

    def sum_custom_values(ids, cf)
      CustomValue.where(customized_type: 'Issue', custom_field_id: cf, customized_id: ids)
                 .pluck(:value)
                 .sum { |v| parse_number(v) }
    end

    def open_versions
      @open_versions ||= begin
        versions = @project.shared_versions.open.includes(:sanan_agile_version_meta).to_a
        versions.reject! { |v| excluded_version_ids.include?(v.id) } if excluded_version_ids.any?
        versions.sort_by { |v| [v.effective_date || Date.new(9999, 1, 1), v.id] }
      end
    end

    def excluded_version_ids
      @excluded_version_ids ||= (
        SananAgile::IntakeSource.intake_queue_version_ids(@cfg) +
        SananAgile::ProductBacklog.version_ids(@cfg)
      ).uniq
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
