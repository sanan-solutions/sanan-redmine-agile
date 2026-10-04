# frozen_string_literal: true

module SananAgile
  # Epic-level dependencies for the roadmap, from Redmine relations between Epics or their Stories,
  # across projects. Redmine stores "blocked by" / "follows" reversed, so only blocks/precedes are read:
  # "A blocks B" or "A precedes B" ⇒ B's Epic depends on A's Epic.
  class RoadmapDependencies
    TYPES = [IssueRelation::TYPE_BLOCKS, IssueRelation::TYPE_PRECEDES].freeze

    # members: { epic_id => [story ids] } for the Epics being shown.
    def initialize(members, user: User.current)
      @members = members
      @user = user
      @epic_tracker_by_project = {}
    end

    # => { epic_id => { depends_on: [ref], blocking: [ref] } }, ref = { id:, subject:, project:, type:,
    #    closed:, year:, quarter:, end_year:, end_quarter: }
    def call
      owner = {}
      @members.each do |epic_id, story_ids|
        owner[epic_id] = epic_id
        story_ids.each { |sid| owner[sid] = epic_id }
      end
      return {} if owner.empty?

      ids = owner.keys
      rels = IssueRelation.where(relation_type: TYPES)
                          .where('issue_from_id IN (:ids) OR issue_to_id IN (:ids)', ids: ids)
                          .pluck(:issue_from_id, :issue_to_id, :relation_type)
      return {} if rels.empty?

      resolve_external!(owner, rels.flat_map { |f, t, _| [f, t] } - ids)

      pairs = rels.filter_map do |from, to, type|
        a = owner[from]
        b = owner[to]
        [a, b, type] if a && b && a != b
      end.uniq { |a, b, _| [a, b] }
      return {} if pairs.empty?

      refs = epic_refs(pairs.flat_map { |a, b, _| [a, b] }.uniq)
      out = Hash.new { |h, k| h[k] = { depends_on: [], blocking: [] } }
      pairs.each do |blocker, dependent, type|
        next unless refs[blocker] && refs[dependent]

        out[dependent][:depends_on] << refs[blocker].merge(type: type) if @members.key?(dependent)
        out[blocker][:blocking] << refs[dependent].merge(type: type) if @members.key?(blocker)
      end
      out
    end

    private

    # Maps issues outside the shown Epics to their Epic (the issue itself, or its parent), per project config.
    def resolve_external!(owner, ext_ids)
      return if ext_ids.empty?

      issues = Issue.visible.where(id: ext_ids).to_a
      parents = Issue.visible.where(id: issues.map(&:parent_id).compact).index_by(&:id)
      issues.each do |issue|
        if epic?(issue)
          owner[issue.id] = issue.id
        elsif (parent = parents[issue.parent_id]) && epic?(parent)
          owner[issue.id] = parent.id
        end
      end
    end

    def epic?(issue)
      et = @epic_tracker_by_project[issue.project_id] ||=
        SananAgile::ProjectSettings.load(issue.project_id)['epic_tracker'].to_i
      et.positive? && issue.tracker_id == et
    end

    def epic_refs(epic_ids)
      issues = Issue.visible.where(id: epic_ids).includes(:status, :project).index_by(&:id)
      items = SananRoadmapItem.where(issue_id: epic_ids).index_by(&:issue_id)
      issues.transform_values do |issue|
        item = items[issue.id]
        {
          id: issue.id,
          subject: issue.subject,
          project_id: issue.project_id,
          project: issue.project.name,
          closed: issue.closed?,
          year: item&.year,
          quarter: item&.quarter,
          end_year: item&.end_year,
          end_quarter: item&.end_quarter
        }
      end
    end
  end
end
