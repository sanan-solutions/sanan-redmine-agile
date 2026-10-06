# frozen_string_literal: true

require_dependency File.expand_path('priority_icon', __dir__)

module SananAgile
  # Agile board backlog panel: open tickets of the Product Backlog or an upcoming sprint, dragged onto a
  # board column to bring them into the board's sprint (status = the column, optional "This sprint" SP).
  module BoardBacklog
    TEAM_PARTS = { 'be' => 'sp_be_cfid', 'fe' => 'sp_fe_cfid', 'qa' => 'sp_qa_cfid' }.freeze
    PAGE_SIZE = 30

    module_function

    # Sprint the board shows: its single Target version filter value, else the project's active sprint.
    # Only an open sprint (not the Product Backlog / an intake queue) can receive tickets.
    def target_version(project, query, cfg)
      return nil unless project

      version = filtered_version(project, query) || project.default_version
      return nil unless version && version.status == 'open'
      return nil if non_sprint_ids(cfg).include?(version.id)

      version
    end

    def filtered_version(project, query)
      filters = (query.respond_to?(:filters) && query.filters) || {}
      filter = filters['fixed_version_id'] || filters[:fixed_version_id]
      return nil unless filter

      op = filter[:operator] || filter['operator']
      values = Array(filter[:values] || filter['values']).reject(&:blank?)
      return nil unless op.to_s == '=' && values.size == 1
      return project.default_version if values.first.to_s == 'current_version'

      project.shared_versions.find_by(id: values.first.to_i)
    end

    def non_sprint_ids(cfg)
      (SananAgile::ProductBacklog.version_ids(cfg) + SananAgile::IntakeSource.intake_queue_version_ids(cfg)).uniq
    end

    # Product Backlog first, then the other open sprints by due date (the board's sprint excluded).
    def sources(project, cfg, target_id)
      excluded = non_sprint_ids(cfg) + [target_id.to_i]
      sprints = project.shared_versions.open.reject { |v| excluded.include?(v.id) }
                       .sort_by { |v| [v.effective_date || Date.new(9999, 1, 1), v.id] }
      [{ value: 'backlog', label: I18n.t(:label_sanan_board_backlog_source_backlog) }] +
        sprints.map { |v| { value: v.id.to_s, label: v.name } }
    end

    # Team parts the ticket can take a "This sprint" SP for: configured and enabled for its tracker.
    def sp_parts(issue, cfg)
      available = issue.available_custom_fields.map(&:id)
      TEAM_PARTS.filter_map do |part, key|
        cfid = cfg[key].to_i
        part if cfid.positive? && available.include?(cfid)
      end
    end

    # Per ticket of one page: SP to plan with (as the Backlog), Size and This-sprint parts, Done BE / FE sprint,
    # sub-task progress.
    def extras(issues, cfg)
      ids = Array(issues).map(&:id)
      return {} if ids.empty?

      plan = SananAgile::IssueSp.planning_sp(ids, cfg)
      size = SananAgile::IssueSp.values_for(ids, cfg, :size)
      sprint = SananAgile::IssueSp.values_for(ids, cfg, :sprint)
      done = { be: done_sprints(ids, cfg['done_be_cfid']), fe: done_sprints(ids, cfg['done_fe_cfid']) }
      children = Issue.where(parent_id: ids).group(:parent_id).count
      closed = Issue.joins(:status).where(parent_id: ids, issue_statuses: { is_closed: true }).group(:parent_id).count
      ids.to_h do |iid|
        [iid, {
          sp: plan[iid],
          size: parts_hash(size[iid]),
          sprint: parts_hash(sprint[iid]),
          done_be: done[:be][iid],
          done_fe: done[:fe][iid],
          subtasks: children[iid].to_i.positive? ? { done: closed[iid].to_i, total: children[iid].to_i } : nil
        }]
      end
    end

    def parts_hash(values)
      return {} unless values

      SananAgile::IssueSp::PARTS.to_h { |part| [part, values[part]] }.compact
    end

    def number(raw)
      return nil if raw.nil? || raw.to_s.strip.empty?

      n = Float(raw.to_s.tr(',', '.'))
      n == n.to_i ? n.to_i : n
    rescue ArgumentError, TypeError
      nil
    end

    # { issue_id => sprint name } of a "Done … in sprint" field (version or text format).
    def done_sprints(ids, cfid)
      cfid = cfid.to_i
      return {} unless cfid.positive?

      pairs = CustomValue.where(customized_type: 'Issue', custom_field_id: cfid, customized_id: ids)
                         .where.not(value: [nil, '']).pluck(:customized_id, :value)
      names = Version.where(id: pairs.map { |_, v| v.to_i }.select(&:positive?)).pluck(:id, :name).to_h
      pairs.to_h { |iid, v| [iid, names[v.to_i] || v.to_s] }
    end

    def issue_json(issue, cfg, extra = {})
      extra ||= {}
      {
        id: issue.id,
        subject: issue.subject,
        tracker: issue.tracker&.name.to_s,
        tracker_id: issue.tracker_id,
        status: issue.status&.name.to_s,
        priority: issue.priority&.name.to_s,
        priority_key: SananAgile::PriorityIcon.key(issue.priority),
        assignee: issue.assigned_to&.name.to_s,
        url: Rails.application.routes.url_helpers.issue_path(issue),
        sp_parts: sp_parts(issue, cfg),
        sp: extra[:sp],
        done_be: extra[:done_be],
        done_fe: extra[:done_fe],
        subtasks: extra[:subtasks],
        sprint_sp: extra[:sprint] || {},
        size: extra[:size] || {}
      }
    end
  end
end
