# frozen_string_literal: true

module SananAgile
  # Story points of an issue, all held in issue custom fields:
  #   Size   — estimate of the whole ticket (does not change per sprint): BE / FE / QA / Total;
  #   Sprint — "This sprint" SP of the current / next sprint: BE / FE / QA / Total. A sub-task carries only the
  #            sprint Total, as its personal SP. When a ticket leaves a sprint the four values are snapshot into
  #            sanan_issue_sprint_sps (history per sprint) and cleared (SprintSpHistory).
  # The Total of each group defaults to the formula of its parts (SpTotalFormula) and can be set by hand.
  module IssueSp
    PARTS = %i[be fe qa total].freeze
    KEYS = {
      size: { be: 'size_be_cfid', fe: 'size_fe_cfid', qa: 'size_qa_cfid', total: 'story_point_cfid' },
      sprint: { be: 'sp_be_cfid', fe: 'sp_fe_cfid', qa: 'sp_qa_cfid', total: 'sp_sprint_total_cfid' }
    }.freeze

    # Row-like view of one group of values (sp_be / sp_fe / sp_qa / sp_total), nil when unset.
    Values = Struct.new(:sp_be, :sp_fe, :sp_qa, :sp_total) do
      def [](part)
        public_send(:"sp_#{part}")
      end

      def any?
        to_a.any? { |v| !v.nil? }
      end

      def team_total
        [sp_be, sp_fe, sp_qa].compact.sum.to_f
      end
    end

    module_function

    def cfid(cfg, group, part)
      cfg.to_h[KEYS.fetch(group).fetch(part)].to_i
    end

    def cfids(cfg, group, parts = PARTS)
      parts.map { |part| cfid(cfg, group, part) }.select(&:positive?)
    end

    def number(raw)
      s = raw.to_s.strip.tr(',', '.')
      return nil if s.empty?

      f = Float(s)
      f == f.to_i ? f.to_i : f
    rescue ArgumentError, TypeError
      nil
    end

    def format(value)
      n = number(value)
      n.nil? ? '' : n.to_s
    end

    # One issue (in-memory values, including unsaved changes).
    def values(issue, cfg, group)
      Values.new(*PARTS.map do |part|
        id = cfid(cfg, group, part)
        id.positive? ? number(issue.custom_field_value(id)) : nil
      end)
    end

    # { issue_id => Values } for many issues (one query); issues without any value are left out.
    def values_for(ids, cfg, group)
      ids = Array(ids).map(&:to_i).uniq
      by_cf = PARTS.to_h { |part| [cfid(cfg, group, part), part] }.reject { |id, _| id <= 0 }
      return {} if ids.empty? || by_cf.empty?

      raw = CustomValue.where(customized_type: 'Issue', customized_id: ids, custom_field_id: by_cf.keys)
                       .where.not(value: [nil, '']).pluck(:customized_id, :custom_field_id, :value)
      raw.each_with_object({}) do |(iid, cf_id, value), h|
        (h[iid] ||= Values.new)[:"sp_#{by_cf[cf_id]}"] = number(value)
      end
    end

    # Sprint Total of each issue: the stored Total, else the formula of its sprint parts.
    def sprint_totals(ids, cfg)
      values_for(ids, cfg, :sprint).transform_values { |v| total_of(v, cfg) }.compact
    end

    def total_of(values, cfg)
      return nil unless values
      return values.sp_total unless values.sp_total.nil?

      SananAgile::SpTotalFormula.suggested(values.sp_be, values.sp_fe, values.sp_qa, cfg: cfg)
    end

    # SP to plan with (Backlog, intake, panel): the sprint estimate when one is set (people re-estimate what
    # is left after a sprint), else the Size Total for a ticket that never was on a sprint. nil = to re-estimate.
    def planning_sp(ids, cfg)
      ids = Array(ids).map(&:to_i).uniq
      return {} if ids.empty?

      sprint = sprint_totals(ids, cfg)
      rest = ids - sprint.keys
      been_on_sprint = rest.any? ? SananIssueSprintSp.where(issue_id: rest).distinct.pluck(:issue_id).to_set : Set.new
      size = values_for(rest - been_on_sprint.to_a, cfg, :size)
      ids.each_with_object({}) do |iid, h|
        h[iid] = if sprint.key?(iid) then sprint[iid]
                 elsif size[iid] then size[iid].sp_total
                 end
      end
    end

    # planning_sp for one issue (its loaded custom values).
    def planning_sp_of(issue, cfg)
      sprint = total_of(values(issue, cfg, :sprint), cfg)
      return sprint unless sprint.nil?
      return nil if issue.id && SananIssueSprintSp.where(issue_id: issue.id).exists?

      values(issue, cfg, :size).sp_total
    end

    def been_on_sprint?(issue)
      issue.id.present? && SananIssueSprintSp.where(issue_id: issue.id).exists?
    end

    # Quick SP edit (Backlog / intake): the estimate to plan with is the sprint Total. A ticket that never was
    # on a sprint and has no Size yet gets it as its Size Total too (its first estimate).
    def assign_planning_sp(issue, cfg, value)
      text = format(value)
      attrs = {}
      total = cfid(cfg, :sprint, :total)
      attrs[total.to_s] = text if total.positive?
      size = cfid(cfg, :size, :total)
      if size.positive? && !been_on_sprint?(issue) && number(issue.custom_field_value(size)).nil?
        attrs[size.to_s] = text
      end
      issue.safe_attributes = { 'custom_field_values' => attrs } if attrs.any?
      attrs.any?
    end

    def sum(values)
      values.compact.sum(0.0)
    end
  end
end
