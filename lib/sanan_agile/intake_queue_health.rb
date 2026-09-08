# frozen_string_literal: true

module SananAgile
  # Ready-queue SLA age + SP threshold alerts for CS/Sale intake.
  class IntakeQueueHealth
    LaneHealth = Struct.new(
      :lane, :ready_sp, :ready_count, :threshold, :over_threshold,
      :sla_days, :over_sla_count, keyword_init: true
    )

    def self.for_project(project, cfg: nil)
      new(project, cfg: cfg)
    end

    def initialize(project, cfg: nil)
      @project = project
      @cfg = cfg || SananAgile::ProjectSettings.load(project.id)
    end

    def lane(lane)
      lane = lane.to_s
      issues = ready_issues(lane)
      ready_sp = issues.sum { |i| story_point_for(i) }
      threshold = threshold_for(lane)
      sla = sla_days
      ready_ids = ready_status_ids(lane)
      over_sla = 0
      if sla.positive?
        issues.each do |issue|
          age = age_days(issue, ready_ids)
          over_sla += 1 if age && age >= sla
        end
      end

      LaneHealth.new(
        lane: lane,
        ready_sp: ready_sp,
        ready_count: issues.size,
        threshold: threshold,
        over_threshold: threshold.positive? && ready_sp >= threshold,
        sla_days: sla,
        over_sla_count: over_sla
      )
    end

    def age_days(issue, ready_ids = nil)
      ready_ids = Array(ready_ids).map(&:to_i).reject(&:zero?)
      return nil if ready_ids.any? && !ready_ids.include?(issue.status_id)

      since = status_since(issue) || issue.updated_on || issue.created_on
      return nil unless since

      (Date.current - since.to_date).to_i
    end

    def sla_breach?(issue, ready_ids = nil)
      days = sla_days
      return false unless days.positive?

      age = age_days(issue, ready_ids)
      age && age >= days
    end

    # At-most-once-per-day mail to Product backlog viewers/managers when over threshold.
    def maybe_alert!(lane)
      health = lane(lane)
      return health unless health.over_threshold
      return health unless mail_enabled?

      cache_key = "sanan_intake_sp_alert/#{@project.id}/#{lane}/#{Date.current}"
      return health if Rails.cache.read(cache_key)

      recipients = alert_recipients
      if recipients.any?
        SananAgileMailer.intake_ready_sp_alert(
          @project, lane, health.ready_sp, health.threshold, recipients
        ).deliver
      end
      Rails.cache.write(cache_key, true, expires_in: 26.hours)
      health
    rescue StandardError => e
      Rails.logger.warn("[sanan_redmine_agile] intake alert failed: #{e.message}")
      health
    end

    private

    def mail_enabled?
      @cfg['intake_ready_sp_alert_mail'].to_s == '1'
    end

    def sla_days
      @cfg['intake_ready_sla_days'].to_i
    end

    def threshold_for(lane)
      key = lane == 'sale' ? 'sale_ready_sp_alert_threshold' : 'cs_ready_sp_alert_threshold'
      @cfg[key].to_f
    end

    def ready_status_ids(lane)
      key = lane == 'sale' ? 'sale_ready_status_ids' : 'cs_ready_status_ids'
      Array(@cfg[key]).map(&:to_i).reject(&:zero?)
    end

    def queue_version_id(lane)
      SananAgile::IntakeSource.queue_version_id(@cfg, lane)
    end

    def ready_issues(lane)
      qid = queue_version_id(lane)
      return [] unless qid.positive?

      scope = Issue.visible.where(project_id: @project.id, fixed_version_id: qid)
      ids = ready_status_ids(lane)
      scope = scope.where(status_id: ids) if ids.any?
      scope.includes(:agile_data).to_a
    end

    def status_since(issue)
      detail = JournalDetail.joins(:journal)
                            .where(journals: { journalized_type: 'Issue', journalized_id: issue.id })
                            .where(property: 'attr', prop_key: 'status_id', value: issue.status_id.to_s)
                            .order(Arel.sql('journals.created_on DESC'))
                            .first
      detail&.journal&.created_on
    end

    def story_point_for(issue)
      cf = @cfg['story_point_cfid'].to_i
      raw = if cf <= 0
              issue.agile_data&.story_points
            else
              issue.custom_value_for(cf)&.value
            end
      parse_number(raw)
    end

    def parse_number(v)
      return 0.0 if v.nil?

      s = v.to_s.strip.tr(',', '.').gsub(/[_\s]/, '')
      return 0.0 if s.empty?

      Float(s)
    rescue ArgumentError, TypeError
      0.0
    end

    def alert_recipients
      users = if @project.respond_to?(:users)
                @project.users.to_a
              else
                @project.members.includes(:principal).map(&:user).compact
              end
      users.select do |u|
        u.is_a?(User) && u.active? && u.mail.present? &&
          (u.allowed_to?(:manage_backlog, @project) || u.allowed_to?(:view_backlog, @project))
      end
    end
  end
end
