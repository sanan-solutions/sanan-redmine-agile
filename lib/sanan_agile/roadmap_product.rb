# frozen_string_literal: true

module SananAgile
  # One product (= project) row of the roadmap board, shared by the project page and the portfolio page.
  module RoadmapProduct
    module_function

    # Whether the project has its own Roadmap tab (project-level page).
    def enabled?(project, cfg = nil)
      cfg ||= SananAgile::ProjectSettings.load(project.id)
      cfg['sanan_agile_enabled'].to_s == '1' && cfg['roadmap_enabled'].to_s == '1'
    end

    # Projects selectable on the portfolio roadmap, in hierarchy order:
    # Sanan Agile module on + view_roadmap permission (the per-project Roadmap tab is not required).
    def available_projects(user = User.current)
      Project.active.has_module(:sanan_agile).sorted.to_a.select do |p|
        user.allowed_to?(:view_roadmap, p)
      end
    end

    # { year:, current_quarter:, statuses:, products: [...] }
    def board(projects, year:, user: User.current, today: Date.today)
      # Load every product first, then resolve Epic dependencies once for all of them.
      prepared = projects.map do |p|
        cfg = SananAgile::ProjectSettings.load(p.id)
        [p, cfg, SananAgile::RoadmapQuery.new(p, cfg: cfg, year: year, today: today).prepare]
      end
      members = prepared.map { |_, _, q| q.members }.reduce({}, :merge)
      deps = SananAgile::RoadmapDependencies.new(members, user: user).call
      {
        year: year,
        current_quarter: today.year == year ? (today.month - 1) / 3 + 1 : 0,
        today: today.to_s,
        statuses: status_legend(projects.first),
        products: prepared.map do |p, cfg, query|
          payload(p, year: year, user: user, today: today, cfg: cfg, data: query.finish(deps))
        end
      }
    end

    def payload(project, year:, user: User.current, today: Date.today, cfg: nil, data: nil)
      cfg ||= SananAgile::ProjectSettings.load(project.id)
      data ||= SananAgile::RoadmapQuery.new(project, cfg: cfg, year: year, today: today).call
      can_manage = user.allowed_to?(:manage_roadmap, project)
      epic_tracker_id = cfg['epic_tracker'].to_i
      # The Epic tracker must also be enabled on the project, or new-issue forms fall back to another tracker.
      epic_tracker_id = 0 unless epic_tracker_id.positive? && project.trackers.where(id: epic_tracker_id).exists?
      {
        id: project.id,
        name: project.name,
        identifier: project.identifier,
        parent_name: project.parent&.name,
        can_manage: can_manage,
        can_add: user.allowed_to?(:add_issues, project) && epic_tracker_id.positive?,
        epic_tracker_id: epic_tracker_id,
        urls: {
          roadmap: enabled?(project, cfg) ? url_helpers.project_product_roadmap_path(project, year: year) : nil,
          move: url_helpers.project_product_roadmap_move_path(project),
          health: url_helpers.project_product_roadmap_health_path(project),
          span: url_helpers.project_product_roadmap_span_path(project),
          baseline: url_helpers.project_product_roadmap_baseline_path(project),
          new_issue: url_helpers.new_project_issue_path(project)
        },
        quarters: data[:quarters],
        continuations: data[:continuations],
        releases: quarter_releases(project, year, user),
        unplanned: can_manage ? data[:unplanned] : [],
        baselines: SananRoadmapBaseline.where(project_id: project.id, year: year).includes(:captured_by)
                                       .to_h { |b| [b.quarter, SananAgile::RoadmapBaseline.review(b, data)] },
        capacity: SananAgile::RoadmapCapacity.new(project, cfg: cfg, year: year, today: today).call
      }
    end

    # Releases (plugin Releases module) due in each quarter of the year: { quarter => [release] }.
    def quarter_releases(project, year, user)
      return {} unless defined?(ReleaseVersion) && user.allowed_to?(:view_releases, project)

      ReleaseVersion.where(project_id: project.id, release_on: Date.new(year, 1, 1)..Date.new(year, 12, 31))
                    .order(:release_on, :id)
                    .group_by { |rv| (rv.release_on.month - 1) / 3 + 1 }
                    .transform_values do |list|
                      list.map do |rv|
                        { id: rv.id, name: rv.name, state: rv.state, release_on: rv.release_on.to_s,
                          url: url_helpers.project_release_path(project, rv) }
                      end
                    end
    end

    def status_legend(project)
      cfg = project ? SananAgile::ProjectSettings.load(project.id) : {}
      query = SananAgile::RoadmapQuery.new(project, cfg: cfg, year: Date.today.year)
      IssueStatus.sorted.map do |st|
        { id: st.id, name: st.name, color: query.status_color(st), closed: st.is_closed? }
      end
    end

    def url_helpers
      Rails.application.routes.url_helpers
    end
  end
end
