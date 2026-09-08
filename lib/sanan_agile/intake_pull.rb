# frozen_string_literal: true

module SananAgile
  # PO pulls issues from CS/Sale queue into a Product sprint or Product backlog.
  class IntakePull
    Result = Struct.new(:ok, :pulled, :skipped, :error, :details, keyword_init: true)

    def self.call(project:, cfg:, lane:, issue_ids:, to_version: nil, user: User.current)
      new(project: project, cfg: cfg, lane: lane, issue_ids: issue_ids,
          to_version: to_version, user: user).call
    end

    def initialize(project:, cfg:, lane:, issue_ids:, to_version:, user:)
      @project = project
      @cfg = cfg
      @lane = lane.to_s
      @issue_ids = Array(issue_ids).map(&:to_i).reject(&:zero?).uniq
      @to_version = to_version
      @user = user
    end

    def call
      return Result.new(ok: false, error: 'invalid_lane') unless %w[cs sale].include?(@lane)
      return Result.new(ok: false, error: 'no_issues') if @issue_ids.blank?

      queue_id = SananAgile::IntakeSource.queue_version_id(@cfg, @lane)
      return Result.new(ok: false, error: 'queue_missing') unless queue_id.positive?

      issues = Issue.where(project_id: @project.id, id: @issue_ids).to_a
      return Result.new(ok: false, error: 'no_issues') if issues.blank?

      ready_ids = ready_status_ids
      invalid = issues.reject { |i| i.fixed_version_id.to_i == queue_id }
      not_ready = ready_ids.any? ? issues.select { |i| !ready_ids.include?(i.status_id) } : []
      if invalid.any? || not_ready.any?
        return Result.new(
          ok: false,
          error: 'invalid_candidates',
          details: {
            not_in_queue: invalid.map(&:id),
            not_ready: not_ready.map(&:id)
          }
        )
      end

      if @to_version
        quota_err = validate_quota!(issues)
        return quota_err if quota_err
      end

      pulled = 0
      skipped = 0
      issues.each do |issue|
        unless @user.allowed_to?(:edit_issues, @project)
          skipped += 1
          next
        end

        issue.init_journal(@user, "[backlog intake by PO] from #{@lane} → #{destination_label}")
        ensure_intake_source!(issue)
        issue.fixed_version = @to_version # nil => Product backlog
        if issue.save
          add_watchers!(issue)
          pulled += 1
        else
          skipped += 1
        end
      end

      Result.new(ok: true, pulled: pulled, skipped: skipped)
    end

    private

    def destination_label
      @to_version ? "sprint #{@to_version.name}" : 'product backlog'
    end

    def ready_status_ids
      key = @lane == 'sale' ? 'sale_ready_status_ids' : 'cs_ready_status_ids'
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

    def validate_quota!(issues)
      quota = quota_for_version(@to_version)
      return nil if quota.nil? # no quota configured = unlimited

      used = used_sp_for_version(@to_version)
      adding = issues.sum { |i| story_point_for(i) }
      if (used + adding) > quota + 1e-6
        return Result.new(
          ok: false,
          error: 'quota_exceeded',
          details: {
            quota: quota,
            used: used,
            adding: adding,
            remaining: [quota - used, 0].max
          }
        )
      end
      nil
    end

    def quota_for_version(version)
      meta = version.sanan_agile_version_meta
      raw = @lane == 'sale' ? meta&.sale_quota_sp : meta&.cs_quota_sp
      return nil if raw.nil?

      raw.to_f
    end

    def used_sp_for_version(version)
      scope = Issue.where(project_id: @project.id, fixed_version_id: version.id)
      cf = SananAgile::IntakeSource.cfid(@cfg)
      return 0.0 if cf <= 0

      aliases = @lane == 'sale' ? %w[sale sales] : %w[cs customer_service customer-service]
      ids = scope.joins(:custom_values)
                 .where(custom_values: { custom_field_id: cf })
                 .where('LOWER(custom_values.value) IN (?)', aliases)
                 .distinct
                 .pluck(:id)
      Issue.where(id: ids).includes(:agile_data).sum { |i| story_point_for(i) }
    end

    def ensure_intake_source!(issue)
      current = SananAgile::IntakeSource.value_for(issue, @cfg)
      return if current == @lane

      SananAgile::IntakeSource.set!(issue, @cfg, @lane)
    end

    def add_watchers!(issue)
      watchers = []
      watchers << issue.author if issue.author
      watchers << issue.assigned_to if issue.assigned_to.is_a?(User)
      watchers.compact.uniq.each do |user|
        next if user.anonymous?
        next if issue.watched_by?(user)

        issue.set_watcher(user, true) if issue.respond_to?(:set_watcher)
      end
    rescue StandardError => e
      Rails.logger.warn("[sanan_redmine_agile] add_watchers failed: #{e.message}")
    end
  end
end
