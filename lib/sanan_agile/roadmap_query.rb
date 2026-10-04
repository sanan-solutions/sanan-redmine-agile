# frozen_string_literal: true

module SananAgile
  # Builds the quarterly Product Roadmap for one project/year.
  # Epic = issue of cfg['epic_tracker']; Story = direct child of an Epic (sub-task trackers excluded).
  # Quarter placement lives in SananRoadmapItem, not in the issue dates.
  class RoadmapQuery
    QUARTERS = [1, 2, 3, 4].freeze
    DEFAULT_OPEN_COLOR = '#94a3b8'
    DEFAULT_CLOSED_COLOR = '#22c55e'

    BLOCKED_STATUS_PATTERN = /block/i

    def initialize(project, cfg:, year:, today: Date.today)
      @project = project
      @cfg = cfg || {}
      @year = year.to_i
      @today = today
    end

    def epic_tracker_id
      @cfg['epic_tracker'].to_i
    end

    def call
      prepare
      finish(SananAgile::RoadmapDependencies.new(members).call)
    end

    # Phase 1: load Epics + Stories. Callers showing several products batch dependencies over
    # all their `members` (one RoadmapDependencies run) before calling #finish.
    def prepare
      @epics = []
      @stories_by_epic = {}
      return self if epic_tracker_id <= 0

      @items_by_issue = SananRoadmapItem.where(project_id: @project.id).index_by(&:issue_id)
      @epics = Issue.visible
                    .where(project_id: @project.id, tracker_id: epic_tracker_id)
                    .includes(:status, :assigned_to)
                    .to_a
      @stories_by_epic = load_stories(@epics.map(&:id))
      self
    end

    # { epic_id => [story ids] } of the prepared Epics.
    def members
      @epics.to_h { |e| [e.id, (@stories_by_epic[e.id] || []).map { |s| s[:id] }] }
    end

    # Phase 2: serialize and place Epics. deps = RoadmapDependencies#call result (may cover other projects).
    def finish(deps)
      return empty_result if epic_tracker_id <= 0

      epics = @epics
      items_by_issue = @items_by_issue
      stories_by_epic = @stories_by_epic
      @moves_by_epic = SananRoadmapMove.where(issue_id: epics.map(&:id)).includes(:user)
                                       .order(:created_at, :id).group_by(&:issue_id)
      @releases_by_epic = releases_by_epic(members)
      deps ||= {}

      quarters = QUARTERS.index_with { [] }
      continuations = QUARTERS.index_with { [] }
      unplanned = []
      # Every visible Epic of the project, wherever it is planned (baseline review needs the ones moved away).
      all_epics = {}
      epics.each do |epic|
        item = items_by_issue[epic.id]
        ser = serialize_epic(epic, item, stories_by_epic[epic.id])
        annotate_dependencies!(ser, deps[epic.id])
        ser[:suggestion] = health_suggestion(ser)
        all_epics[epic.id] = ser
        if item.nil?
          unplanned << ser unless epic.closed?
          next
        end
        quarters[item.quarter] << ser if item.year == @year
        # Later quarters of a multi-quarter Epic (also when it started in an earlier year).
        QUARTERS.each do |q|
          next if item.year == @year && item.quarter == q
          next unless item.covers?(@year, q)

          continuations[q] << { id: epic.id, subject: epic.subject, progress: ser[:progress], color: ser[:color],
                                from: SananRoadmapMove.label(item.year, item.quarter), in_data: item.year == @year }
        end
      end
      quarters.each_value { |list| list.sort_by! { |e| [e[:position], e[:id]] } }
      unplanned.sort_by! { |e| -e[:id] }

      {
        year: @year,
        quarters: quarters,
        continuations: continuations,
        unplanned: unplanned,
        all_epics: all_epics,
        statuses: status_legend
      }
    end

    private

    # Blockers that are open and unplanned, or finish after this Epic starts, are conflicts.
    # Same quarter is allowed (both can land in order inside the quarter).
    def annotate_dependencies!(ser, dep)
      dep ||= { depends_on: [], blocking: [] }
      start = ser[:quarter] && SananRoadmapItem.key(ser[:year], ser[:quarter])
      finish = ser[:quarter] && SananRoadmapItem.key(ser[:end_year] || ser[:year], ser[:end_quarter] || ser[:quarter])
      ser[:depends_on] = dep[:depends_on].map do |d|
        d.merge(conflict: start ? late?(d, start) : false)
      end
      ser[:blocking] = dep[:blocking].map do |d|
        d_start = d[:quarter] && SananRoadmapItem.key(d[:year], d[:quarter])
        d.merge(conflict: !d[:closed] && d_start && !ser[:closed] && (finish.nil? || finish > d_start) ? true : false)
      end
      ser[:dep_conflict] = ser[:depends_on].any? { |d| d[:conflict] }
    end

    def late?(dep, start)
      return false if dep[:closed]
      return true unless dep[:quarter]

      SananRoadmapItem.key(dep[:end_year] || dep[:year], dep[:end_quarter] || dep[:quarter]) > start
    end

    # Suggested health (never applied automatically): time elapsed vs. progress, Blocked stories,
    # dependency conflicts. nil when the Epic is unplanned or closed.
    def health_suggestion(ser)
      return nil if ser[:quarter].nil? || ser[:closed]

      level = 0
      reasons = []
      q_start = Date.new(ser[:year], (ser[:quarter] - 1) * 3 + 1, 1)
      end_y = ser[:end_year] || ser[:year]
      end_q = ser[:end_quarter] || ser[:quarter]
      q_end = Date.new(end_y, (end_q - 1) * 3 + 1, 1).end_of_quarter
      if @today > q_end && ser[:progress] < 100
        level = 2
        reasons << ::I18n.t(:text_sanan_roadmap_hs_overdue, until: "Q#{end_q}/#{end_y}")
      elsif @today >= q_start
        elapsed = (((@today - q_start).to_i + 1) * 100.0 / ((q_end - q_start).to_i + 1)).round
        gap = elapsed - ser[:progress]
        if gap >= 40 then level = 2
        elsif gap >= 20 then level = [level, 1].max
        end
        reasons << ::I18n.t(:text_sanan_roadmap_hs_pace, progress: ser[:progress], elapsed: elapsed) if gap >= 20
      end
      blocked = ser[:stories].count { |s| !s[:closed] && blocked_status?(s) }
      if blocked.positive?
        level = [level, 1].max
        reasons << ::I18n.t(:text_sanan_roadmap_hs_blocked, n: blocked)
      end
      if ser[:dep_conflict]
        level = [level, 1].max
        reasons << ::I18n.t(:text_sanan_roadmap_hs_dependency)
      end
      { health: SananRoadmapItem::HEALTH_VALUES[level], reasons: reasons }
    end

    # Configured Blocked statuses; without configuration, any status whose name contains "block".
    def blocked_status?(story)
      ids = blocked_status_ids
      ids.any? ? ids.include?(story[:status_id]) : story[:status].to_s.match?(BLOCKED_STATUS_PATTERN)
    end

    def blocked_status_ids
      @blocked_status_ids ||= Array(@cfg['roadmap_blocked_status_ids']).map(&:to_i).reject(&:zero?)
    end

    # Releases reached through the Epic itself or its Stories (release_items).
    def releases_by_epic(members)
      return {} unless defined?(ReleaseItem)

      owner = {}
      members.each do |epic_id, story_ids|
        owner[epic_id] = epic_id
        story_ids.each { |sid| owner[sid] = epic_id }
      end
      return {} if owner.empty?

      ReleaseItem.where(issue_id: owner.keys).includes(:release_version).each_with_object({}) do |ri, h|
        rv = ri.release_version
        next unless rv

        list = (h[owner[ri.issue_id]] ||= [])
        next if list.any? { |r| r[:id] == rv.id }

        list << { id: rv.id, name: rv.name, state: rv.state, release_on: rv.release_on&.to_s }
      end
    end

    public

    def status_color(status)
      raw = (@cfg['roadmap_status_colors'] || {})[status.id.to_s].to_s.strip
      return raw if raw.match?(/\A#[0-9A-Fa-f]{6}\z/)

      status.is_closed? ? DEFAULT_CLOSED_COLOR : DEFAULT_OPEN_COLOR
    end

    private

    def empty_result
      { year: @year, quarters: QUARTERS.index_with { [] }, continuations: QUARTERS.index_with { [] },
        unplanned: [], all_epics: {}, statuses: status_legend }
    end

    def load_stories(epic_ids)
      return {} if epic_ids.empty?

      scope = Issue.visible.where(parent_id: epic_ids).includes(:status, :assigned_to, :tracker)
      scope = scope.where.not(tracker_id: subtask_tracker_ids) if subtask_tracker_ids.any?
      stories = scope.order(:id).to_a
      sp = story_points_for(stories.map(&:id))
      stories.group_by(&:parent_id).transform_values do |list|
        list.map { |s| serialize_story(s, sp[s.id]) }
      end
    end

    def serialize_epic(epic, item, stories)
      stories ||= []
      sp_total = stories.sum { |s| s[:sp].to_f }
      sp_done = stories.select { |s| s[:closed] }.sum { |s| s[:sp].to_f }
      done_count = stories.count { |s| s[:closed] }

      {
        id: epic.id,
        subject: epic.subject,
        status_id: epic.status_id,
        status: epic.status&.name.to_s,
        color: status_color(epic.status),
        closed: epic.closed?,
        owner: epic.assigned_to&.name,
        health: item ? item.health_key : 'on_track',
        position: item ? item.position.to_i : 0,
        year: item&.year,
        quarter: item&.quarter,
        end_year: item&.end_year,
        end_quarter: item&.end_quarter,
        span: item ? item.span : 1,
        releases: (@releases_by_epic || {})[epic.id] || [],
        progress: epic_progress(epic, stories, sp_total, sp_done, done_count),
        sp_total: round_sp(sp_total),
        sp_done: round_sp(sp_done),
        story_count: stories.size,
        done_count: done_count,
        stories: stories,
        moves: serialize_moves(@moves_by_epic.to_h[epic.id], item)
      }
    end

    # Quarter-change history: slips (planned → later quarter) and where the Epic was first planned.
    def serialize_moves(moves, item)
      moves ||= []
      # First quarter the Epic was planned in: where the first move started from, else its first destination.
      first = moves.first
      origin_yq = if first&.from_quarter then [first.from_year, first.from_quarter]
                  elsif (m = moves.detect(&:to_quarter)) then [m.to_year, m.to_quarter]
                  end
      {
        count: moves.size,
        slips: moves.count(&:slip?),
        origin: origin_yq && SananRoadmapMove.label(*origin_yq),
        # Flagged only while the Epic actually sits later than where it was first planned.
        slipped: !!(origin_yq && item && item.start_key > SananRoadmapItem.key(*origin_yq)),
        history: moves.last(10).map do |m|
          { from: m.from_label, to: m.to_label, on: m.created_at.to_date.to_s, by: m.user&.name }
        end
      }
    end

    # SP-weighted when stories carry SP; otherwise share of closed stories.
    def epic_progress(epic, stories, sp_total, sp_done, done_count)
      return epic.closed? ? 100 : epic.done_ratio.to_i if stories.empty?
      return ((sp_done / sp_total) * 100).round if sp_total.positive?

      ((done_count.to_f / stories.size) * 100).round
    end

    def serialize_story(story, sp)
      {
        id: story.id,
        subject: story.subject,
        tracker: story.tracker&.name.to_s,
        status_id: story.status_id,
        status: story.status&.name.to_s,
        color: status_color(story.status),
        closed: story.closed?,
        assignee: story.assigned_to&.name,
        sp: sp.nil? ? nil : round_sp(sp),
        progress: story.closed? ? 100 : story.done_ratio.to_i
      }
    end

    def story_points_for(ids)
      return {} if ids.empty?

      cf = @cfg['story_point_cfid'].to_i
      if cf.positive?
        CustomValue.where(customized_type: 'Issue', custom_field_id: cf, customized_id: ids)
                   .pluck(:customized_id, :value)
                   .each_with_object({}) { |(id, v), h| n = parse_number(v); h[id] = n unless n.nil? }
      elsif defined?(AgileData)
        AgileData.where(issue_id: ids).where.not(story_points: nil).pluck(:issue_id, :story_points)
                 .to_h { |id, v| [id, v.to_f] }
      else
        {}
      end
    end

    def status_legend
      IssueStatus.sorted.map do |st|
        { id: st.id, name: st.name, color: status_color(st), closed: st.is_closed? }
      end
    end

    def subtask_tracker_ids
      @subtask_tracker_ids ||= Array(@cfg['subtask_tracker']).map(&:to_i).reject(&:zero?)
    end

    def round_sp(n)
      f = n.to_f.round(1)
      f == f.to_i ? f.to_i : f
    end

    def parse_number(v)
      s = v.to_s.strip.tr(',', '.')
      return nil if s.empty?

      Float(s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
