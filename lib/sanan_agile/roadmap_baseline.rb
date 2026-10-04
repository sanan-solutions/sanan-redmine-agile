# frozen_string_literal: true

module SananAgile
  # Quarter baseline: lock the Epics planned in a quarter, then review plan vs. actual.
  module RoadmapBaseline
    module_function

    SNAPSHOT_KEYS = %i[id subject sp_total sp_done story_count done_count].freeze
    # Review states, in display order.
    STATES = %w[done in_progress slipped moved dropped added].freeze

    def capture!(project, year:, quarter:, user:, cfg: nil)
      cfg ||= SananAgile::ProjectSettings.load(project.id)
      data = SananAgile::RoadmapQuery.new(project, cfg: cfg, year: year).call
      baseline = SananRoadmapBaseline.find_or_initialize_by(project_id: project.id, year: year, quarter: quarter)
      baseline.epics = data[:quarters][quarter].map { |e| e.slice(*SNAPSHOT_KEYS) }
      baseline.captured_at = Time.now
      baseline.captured_by_id = user&.id
      baseline.save!
      baseline
    end

    # Epic counts as delivered when closed, or when all of its stories are closed.
    def done?(epic)
      epic[:closed] || (epic[:story_count].to_i.positive? && epic[:done_count] == epic[:story_count])
    end

    # data = RoadmapQuery#call for the baseline's year (needs :quarters and :all_epics).
    def review(baseline, data)
      key = quarter_key(baseline.year, baseline.quarter)
      all = data[:all_epics] || {}
      baseline_ids = []

      rows = baseline.epics.map do |snap|
        id = snap['id'].to_i
        baseline_ids << id
        now = all[id]
        {
          id: id,
          subject: now ? now[:subject] : snap['subject'],
          state: state_for(now, key),
          now_in: now && now[:quarter] ? "Q#{now[:quarter]}/#{now[:year]}" : nil,
          sp_baseline: snap['sp_total'].to_f,
          sp_now: now ? now[:sp_total].to_f : nil,
          sp_done: now ? now[:sp_done].to_f : 0.0
        }
      end

      added = (data[:quarters][baseline.quarter] || []).reject { |e| baseline_ids.include?(e[:id]) }.map do |e|
        { id: e[:id], subject: e[:subject], state: 'added', now_in: "Q#{baseline.quarter}/#{baseline.year}",
          sp_baseline: nil, sp_now: e[:sp_total].to_f, sp_done: e[:sp_done].to_f }
      end

      committed = rows.sum { |r| r[:sp_baseline] }
      {
        id: baseline.id,
        year: baseline.year,
        quarter: baseline.quarter,
        captured_at: baseline.captured_at.to_date.to_s,
        captured_by: baseline.captured_by&.name,
        summary: {
          committed_epics: rows.size,
          counts: STATES.index_with { |s| (rows + added).count { |r| r[:state] == s } },
          sp_committed: round(committed),
          sp_done: round(rows.sum { |r| r[:sp_done] }),
          sp_added: round(added.sum { |r| r[:sp_now] })
        },
        epics: rows + added
      }
    end

    def state_for(now, key)
      return 'dropped' if now.nil?           # deleted or no longer visible
      return 'done' if done?(now)
      return 'dropped' if now[:quarter].nil? # back to Unplanned

      current = quarter_key(now[:year], now[:quarter])
      return 'slipped' if current > key
      return 'moved' if current < key

      'in_progress'
    end

    def quarter_key(year, quarter)
      year.to_i * 4 + quarter.to_i
    end

    def round(n)
      f = n.to_f.round(1)
      f == f.to_i ? f.to_i : f
    end
  end
end
