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

    # Per ticket of one page: SP (the backlog's SP column), Done BE / FE sprint, sub-task progress.
    def extras(issues, cfg)
      ids = Array(issues).map(&:id)
      return {} if ids.empty?

      sp = story_points(ids, cfg)
      done = { be: done_sprints(ids, cfg['done_be_cfid']), fe: done_sprints(ids, cfg['done_fe_cfid']) }
      sprint = sprint_sp(issues, cfg)
      children = Issue.where(parent_id: ids).group(:parent_id).count
      closed = Issue.joins(:status).where(parent_id: ids, issue_statuses: { is_closed: true }).group(:parent_id).count
      ids.to_h do |iid|
        [iid, {
          sp: sp[iid],
          done_be: done[:be][iid],
          done_fe: done[:fe][iid],
          sprint: sprint[iid],
          subtasks: children[iid].to_i.positive? ? { done: closed[iid].to_i, total: children[iid].to_i } : nil
        }]
      end
    end

    def story_points(ids, cfg)
      cfid = cfg['story_point_cfid'].to_i
      raw = if cfid.positive?
              CustomValue.where(customized_type: 'Issue', custom_field_id: cfid, customized_id: ids)
                         .where.not(value: [nil, '']).pluck(:customized_id, :value)
            elsif defined?(AgileData)
              AgileData.where(issue_id: ids).where.not(story_points: nil).pluck(:issue_id, :story_points)
            else
              []
            end
      raw.each_with_object({}) do |(iid, value), h|
        n = Float(value.to_s.tr(',', '.')) rescue nil
        h[iid] = (n == n.to_i ? n.to_i : n) if n
      end
    end

    # "This sprint" SP of tickets sitting on a sprint (an upcoming sprint as the panel's source): team values
    # and the sprint Total. Product Backlog tickets have none.
    def sprint_sp(issues, cfg)
      on_sprint = Array(issues).select do |i|
        i.fixed_version_id.to_i.positive? && !non_sprint_ids(cfg).include?(i.fixed_version_id)
      end
      return {} if on_sprint.empty?

      ids = on_sprint.map(&:id)
      parts = TEAM_PARTS.to_h do |part, key|
        cfid = cfg[key].to_i
        values = if cfid.positive?
                   CustomValue.where(customized_type: 'Issue', custom_field_id: cfid, customized_id: ids)
                              .where.not(value: [nil, '']).pluck(:customized_id, :value).to_h
                 else
                   {}
                 end
        [part.to_sym, values]
      end
      totals = if defined?(SananIssueSprintSp)
                 on_sprint.each_with_object({}) do |i, h|
                   row = SananIssueSprintSp.find_by(issue_id: i.id, version_id: i.fixed_version_id)
                   h[i.id] = row&.sp_total
                 end
               else
                 {}
               end
      on_sprint.each_with_object({}) do |i, h|
        values = parts.transform_values { |m| number(m[i.id]) }.compact
        values[:total] = number(totals[i.id]) unless totals[i.id].nil?
        h[i.id] = values if values.any?
      end
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

    def issue_json(issue, cfg, sizes, extra = {})
      size = sizes[issue.id]
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
        sprint_sp: extra[:sprint],
        size: size ? { be: number(size.sp_be), fe: number(size.sp_fe), qa: number(size.sp_qa) }.compact : {}
      }
    end
  end
end
