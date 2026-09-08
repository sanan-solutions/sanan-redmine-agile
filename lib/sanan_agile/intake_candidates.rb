# frozen_string_literal: true

module SananAgile
  # Candidates + quota stats for PO pull UI on Product backlog.
  class IntakeCandidates
    def self.for_project(project, cfg: nil)
      new(project, cfg: cfg).call
    end

    def initialize(project, cfg: nil)
      @project = project
      @cfg = cfg || SananAgile::ProjectSettings.load(project.id)
    end

    def call
      {
        cs_enabled: @cfg['cs_backlog_enabled'].to_s == '1',
        sale_enabled: @cfg['sale_backlog_enabled'].to_s == '1',
        cs: lane_payload('cs'),
        sale: lane_payload('sale')
      }
    end

    def quota_stats_for(version)
      {
        cs: lane_quota_stats(version, 'cs'),
        sale: lane_quota_stats(version, 'sale')
      }
    end

    private

    def lane_payload(lane)
      queue_id = SananAgile::IntakeSource.queue_version_id(@cfg, lane)
      return { issues: [], queue_version_id: nil } unless queue_id.positive?

      scope = Issue.visible
                   .where(project_id: @project.id, fixed_version_id: queue_id)
                   .joins(:priority)
                   .eager_load(:agile_data)
                   .includes(:tracker, :status, :priority)
                   .order(Arel.sql(priority_order_sql))

      ready_ids = ready_status_ids(lane)
      scope = scope.where(status_id: ready_ids) if ready_ids.any?

      issues = scope.to_a.map do |issue|
        {
          id: issue.id,
          subject: issue.subject,
          tracker: issue.tracker.name,
          priority: issue.priority&.name,
          priority_id: issue.priority_id,
          status: issue.status.name,
          sp: story_point_for(issue)
        }
      end
      { issues: issues, queue_version_id: queue_id }
    end

    def lane_quota_stats(version, lane)
      meta = version.sanan_agile_version_meta
      quota_raw = lane == 'sale' ? meta&.sale_quota_sp : meta&.cs_quota_sp
      quota = quota_raw.nil? ? nil : quota_raw.to_f
      used = used_sp(version, lane)
      {
        quota: quota,
        used: used,
        remaining: quota.nil? ? nil : [quota - used, 0].max
      }
    end

    def used_sp(version, lane)
      cf = SananAgile::IntakeSource.cfid(@cfg)
      return 0.0 if cf <= 0

      aliases = lane == 'sale' ? %w[sale sales] : %w[cs customer_service customer-service]
      ids = Issue.where(project_id: @project.id, fixed_version_id: version.id)
                 .joins(:custom_values)
                 .where(custom_values: { custom_field_id: cf })
                 .where('LOWER(custom_values.value) IN (?)', aliases)
                 .distinct
                 .pluck(:id)
      Issue.where(id: ids).includes(:agile_data).sum { |i| story_point_for(i) }
    end

    def ready_status_ids(lane)
      key = lane == 'sale' ? 'sale_ready_status_ids' : 'cs_ready_status_ids'
      Array(@cfg[key]).map(&:to_i).reject(&:zero?)
    end

    def story_point_for(issue)
      cf = @cfg['story_point_cfid'].to_i
      return issue.agile_data&.story_points.to_f if cf <= 0

      cv = issue.custom_value_for(cf)
      parse_number(cv&.value)
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
          WHEN 'highest' THEN 1 WHEN 'high2' THEN 2 WHEN 'high3' THEN 3
          WHEN 'high4' THEN 4 WHEN 'high5' THEN 5 WHEN 'default' THEN 6
          WHEN 'low3' THEN 7 WHEN 'low2' THEN 8 WHEN 'lowest' THEN 9
          ELSE 10
        END ASC,
        COALESCE(agile_data.position, 0) DESC,
        issues.id ASC
      SQL
    end
  end
end
