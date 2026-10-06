# frozen_string_literal: true

module SananAgile
  # Team & capacity for the Product Roadmap, from the last N closed sprints.
  # - Team velocity  = SananAgile::Velocity (same Actual SP as the sprint report).
  # - Member effort  = sprint report member rows (closed sub-tasks per assignee), averaged over N.
  # - Quarter capacity = velocity × sprints left in the quarter (sprint length from recent sprints).
  class RoadmapCapacity
    DEFAULT_SPRINT_DAYS = 14
    WINDOWS = SananAgile::Velocity::WINDOWS

    def self.window_from(cfg)
      w = cfg.to_h['roadmap_capacity_window'].to_i
      WINDOWS.include?(w) ? w : WINDOWS.max
    end

    def initialize(project, cfg:, year:, today: Date.today)
      @project = project
      @cfg = cfg || {}
      @year = year.to_i
      @today = today
    end

    def call
      versions = SananAgile::Velocity.new(@project, cfg: @cfg, window: window).recent_closed_sprints
      stats = versions.to_h { |v| [v.id, sprint_stats(v)] }
      versions = versions.select { |v| stats[v.id] }
      members = member_stats(versions, stats)
      member_total = round1(members.sum { |m| m[:avg_sp].to_f })
      # Same rounding as SananAgile::Velocity (backlog), so both pages show the same number.
      velocity = versions.any? ? ((versions.sum { |v| stats[v.id][:sp] } / versions.size) * 2).round / 2.0 : 0.0
      per_sprint = velocity.positive? ? velocity : member_total
      sprint_days = sprint_length(versions)

      {
        window: window,
        sample_size: versions.size,
        sprints: versions.map { |v| { id: v.id, name: v.name, sp: round1(stats[v.id][:sp]) } },
        velocity: round1(per_sprint),
        member_total: member_total,
        sprint_days: sprint_days,
        members: members,
        quarters: quarter_capacity(per_sprint, sprint_days)
      }
    end

    def window
      self.class.window_from(@cfg)
    end

    private

    # Actual SP + per-member SP of one closed sprint. Cached: closed sprints rarely change, and the key
    # moves with the version, its issues and the SP-related settings.
    def sprint_stats(version)
      Rails.cache.fetch(sprint_cache_key(version), expires_in: 12.hours) do
        calc = SananAgile::SprintReport::Calculator.new(version, cfg: @cfg, metrics_only: true)
        {
          sp: calc.call.actual_sp.to_f,
          members: calc.member_breakdown.filter_map { |r| [r.user_id, r.sp.to_f] if r.user_id }
        }
      end
    rescue StandardError => e
      Rails.logger.error "[sanan_agile] Roadmap sprint stats failed for version=#{version.id}: #{e.class}: #{e.message}"
      nil
    end

    def sprint_cache_key(version)
      parent_ids = Issue.where(fixed_version_id: version.id).select(:id)
      touched = Issue.where(fixed_version_id: version.id).or(Issue.where(parent_id: parent_ids)).maximum(:updated_on)
      cfg_keys = %w[story_point_cfid sp_sprint_total_cfid subtask_tracker standard_tracker sp_be_cfid sp_fe_cfid sp_qa_cfid
                    sp_actual_version_cfid dod_cfid]
      digest = Digest::MD5.hexdigest(@cfg.to_h.slice(*cfg_keys).to_json)
      ['sanan_roadmap_sprint', version.id, version.updated_on.to_i, touched.to_i, digest]
    end

    def member_stats(versions, stats)
      sp = Hash.new(0.0)
      active = Hash.new(0)
      versions.each do |v|
        stats[v.id][:members].each do |user_id, user_sp|
          sp[user_id] += user_sp
          active[user_id] += 1
        end
      end

      n = versions.size
      rows = project_members.map do |user, role|
        build_member(user, role, sp[user.id], active[user.id], n)
      end
      # Assignees with effort in the window who are no longer project members.
      known = rows.map { |r| r[:id] }
      extra_ids = sp.keys - known
      User.where(id: extra_ids).each do |user|
        rows << build_member(user, nil, sp[user.id], active[user.id], n)
      end
      rows.sort_by { |r| [r[:role_position], r[:name].downcase] }
    end

    def build_member(user, role, total_sp, active_count, n)
      {
        id: user.id,
        name: user.name,
        initials: initials(user.name),
        role: role&.name,
        role_position: role ? role.position.to_i : 9_999,
        avg_sp: n.positive? && active_count.positive? ? round1(total_sp / n) : nil,
        sprints_active: active_count
      }
    end

    # [[User, primary Role]] for active user memberships (groups skipped).
    def project_members
      @project.memberships.active.includes(:principal, :roles).filter_map do |m|
        user = m.principal
        next unless user.is_a?(User) && user.active?

        [user, m.roles.min_by(&:position)]
      end
    end

    def sprint_length(versions)
      days = versions.filter_map do |v|
        start = v.respond_to?(:sanan_sprint_start_date) ? v.sanan_sprint_start_date : nil
        finish = v.effective_date
        next unless start && finish && finish >= start

        (finish - start).to_i + 1
      end
      return DEFAULT_SPRINT_DAYS if days.empty?

      (days.sum.to_f / days.size).round
    end

    def quarter_capacity(per_sprint, sprint_days)
      (1..4).to_h do |q|
        q_start = Date.new(@year, (q - 1) * 3 + 1, 1)
        q_end = q_start.end_of_quarter
        if q_end < @today
          [q, { past: true, sprints: nil, capacity: nil }]
        else
          from = [q_start, @today].max
          sprints = ((q_end - from).to_i + 1).to_f / sprint_days
          [q, { past: false, sprints: round1(sprints), capacity: round1(per_sprint * sprints) }]
        end
      end
    end

    def initials(name)
      parts = name.to_s.split(/\s+/).reject(&:empty?)
      return '?' if parts.empty?

      (parts.first[0] + (parts.size > 1 ? parts.last[0] : '')).upcase
    end

    def round1(n)
      f = n.to_f.round(1)
      f == f.to_i ? f.to_i : f
    end
  end
end
