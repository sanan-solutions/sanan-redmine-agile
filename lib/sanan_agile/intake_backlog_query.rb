# frozen_string_literal: true

module SananAgile
  class IntakeBacklogQuery
    Section = Struct.new(:key, :label_key, :issues, :sp_total, :editable, keyword_init: true)

    def self.call(project, lane:, cfg: nil, filters: {})
      new(project, lane: lane, cfg: cfg, filters: filters).call
    end

    def initialize(project, lane:, cfg: nil, filters: {})
      @project = project
      @lane = lane.to_s
      @cfg = cfg || SananAgile::ProjectSettings.load(project.id)
      @filters = (filters || {}).with_indifferent_access
    end

    def call
      {
        lane: @lane,
        queue_version: queue_version,
        queue: queue_section,
        in_product: in_product_section,
        trackers: allowed_trackers,
        statuses: IssueStatus.sorted.to_a,
        priorities: IssuePriority.active.to_a,
        assignees: @project.assignable_users.sort_by { |u| u.name.to_s.downcase }
      }
    end

    def story_point_for(issue)
      cf = @cfg['story_point_cfid'].to_i
      return issue.agile_data&.story_points.to_f if cf <= 0

      cv = issue.custom_value_for(cf)
      parse_number(cv&.value)
    end

    private

    def queue_version
      vid = SananAgile::IntakeSource.queue_version_id(@cfg, @lane)
      return nil if vid <= 0

      @project.shared_versions.find_by(id: vid)
    end

    def queue_section
      v = queue_version
      issues = v ? base_scope.where(fixed_version_id: v.id).to_a : []
      Section.new(
        key: 'queue',
        label_key: 'label_intake_section_queue',
        issues: issues,
        sp_total: sum_sp(issues),
        editable: true
      )
    end

    def in_product_section
      issues = in_product_scope.to_a
      Section.new(
        key: 'in_product',
        label_key: 'label_intake_section_in_product',
        issues: issues,
        sp_total: sum_sp(issues),
        editable: false
      )
    end

    def in_product_scope
      scope = base_scope
      queue_id = SananAgile::IntakeSource.queue_version_id(@cfg, @lane)
      scope = scope.where.not(fixed_version_id: queue_id) if queue_id.positive?
      # include unscheduled (nil version) that still have intake source
      cf = SananAgile::IntakeSource.cfid(@cfg)
      if cf.positive?
        scope = scope.joins(:custom_values).where(
          custom_values: { custom_field_id: cf }
        ).where('LOWER(custom_values.value) IN (?)', source_aliases)
         .where.not(id: queue_issue_ids(queue_id))
         .distinct
      elsif queue_id.positive?
        # Without CF we cannot reliably list "taken" issues
        scope = scope.none
      else
        scope = scope.none
      end
      scope.where(status_id: IssueStatus.where(is_closed: false).select(:id))
    end

    def queue_issue_ids(queue_id)
      return [] unless queue_id.positive?

      Issue.where(project_id: @project.id, fixed_version_id: queue_id).pluck(:id)
    end

    def source_aliases
      case @lane
      when 'cs' then %w[cs customer_service customer-service]
      when 'sale' then %w[sale sales]
      else [@lane]
      end
    end

    def base_scope
      @base_scope ||= begin
        scope = Issue.visible
                     .where(project_id: @project.id)
                     .joins(:priority)
                     .eager_load(:agile_data)
                     .includes(:tracker, :status, :priority, :assigned_to, :fixed_version)
                     .order(Arel.sql(priority_order_sql))

        if allowed_tracker_ids.any?
          scope = scope.where(tracker_id: allowed_tracker_ids)
        end

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

        if @filters[:q].present?
          raw = @filters[:q].to_s.strip
          q = "%#{raw.downcase}%"
          scope = if raw =~ /\A\d+\z/
                    scope.where('LOWER(issues.subject) LIKE ? OR issues.id = ?', q, raw.to_i)
                  else
                    scope.where('LOWER(issues.subject) LIKE ?', q)
                  end
        end

        if @filters[:ready_only].to_s == '1'
          ready_ids = ready_status_ids
          scope = scope.where(status_id: ready_ids) if ready_ids.any?
        end

        scope
      end
    end

    def ready_status_ids
      key = @lane == 'sale' ? 'sale_ready_status_ids' : 'cs_ready_status_ids'
      Array(@cfg[key]).map(&:to_i).reject(&:zero?)
    end

    def allowed_tracker_ids
      @allowed_tracker_ids ||= begin
        ids = Array(@cfg['backlog_trackers']).map(&:to_i).reject(&:zero?)
        ids = Array(@cfg['standard_tracker']).map(&:to_i).reject(&:zero?) if ids.blank?
        ids
      end
    end

    def allowed_trackers
      return Tracker.order(:position) if allowed_tracker_ids.blank?

      Tracker.where(id: allowed_tracker_ids).order(:position)
    end

    def subtask_ids
      Array(@cfg['subtask_tracker']).map(&:to_i).reject(&:zero?)
    end

    def hide_subtasks?
      @cfg['backlog_hide_subtasks'].to_s != '0'
    end

    def sum_sp(issues)
      issues.sum { |i| story_point_for(i) }
    end

    def parse_number(v)
      return 0.0 if v.nil?

      s = v.to_s.strip.tr(',', '.').gsub(/[_\s]/, '')
      return 0.0 if s.empty?

      Float(s)
    rescue ArgumentError, TypeError
      0.0
    end

    def priority_order_sql
      <<~SQL.squish
        CASE enumerations.position_name
          WHEN 'highest' THEN 1
          WHEN 'high2' THEN 2
          WHEN 'high3' THEN 3
          WHEN 'high4' THEN 4
          WHEN 'high5' THEN 5
          WHEN 'default' THEN 6
          WHEN 'low3' THEN 7
          WHEN 'low2' THEN 8
          WHEN 'lowest' THEN 9
          ELSE 10
        END ASC,
        COALESCE(agile_data.position, 0) DESC,
        issues.id ASC
      SQL
    end
  end
end
