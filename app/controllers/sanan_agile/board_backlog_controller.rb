# frozen_string_literal: true

# Agile board backlog panel: list tickets of the Product Backlog / an upcoming sprint, and pull one onto a
# board column (sprint = the board's sprint, status = the column, optional "This sprint" team SP).
class SananAgile::BoardBacklogController < ApplicationController
  before_action :find_project_by_project_id
  before_action :authorize
  before_action :load_settings

  def index
    source = params[:source].to_s
    version_id = nil
    unless source.empty? || source == 'backlog'
      version = @project.shared_versions.open.find_by(id: source.to_i)
      return render(json: { error: 'unknown source' }, status: :not_found) unless version

      version_id = version.id
    end

    filters = { q: params[:q], tracker_id: params[:tracker_id] }
    scope = SananAgile::BacklogQuery.new(@project, cfg: @cfg, filters: filters).open_issues_scope(version_id)
    offset = [params[:offset].to_i, 0].max
    issues = scope.offset(offset).limit(SananAgile::BoardBacklog::PAGE_SIZE + 1).to_a
    has_more = issues.size > SananAgile::BoardBacklog::PAGE_SIZE
    issues = issues.first(SananAgile::BoardBacklog::PAGE_SIZE)
    sizes = defined?(SananIssueSpSize) ? SananIssueSpSize.where(issue_id: issues.map(&:id)).index_by(&:issue_id) : {}
    extras = SananAgile::BoardBacklog.extras(issues, @cfg)

    render json: {
      sources: SananAgile::BoardBacklog.sources(@project, @cfg, params[:target_version_id]),
      issues: issues.map { |i| SananAgile::BoardBacklog.issue_json(i, @cfg, sizes, extras[i.id]) },
      has_more: has_more,
      next_offset: offset + issues.size
    }
  end

  def pull
    issue = @project.issues.visible.find_by(id: params[:issue_id])
    return render_errors([l(:error_sanan_board_pull_not_found)], :not_found) unless issue
    return render_errors([l(:error_sanan_board_pull_forbidden)], :forbidden) unless issue.editable?

    version = @project.shared_versions.open.find_by(id: params[:version_id])
    if version.nil? || SananAgile::BoardBacklog.non_sprint_ids(@cfg).include?(version.id)
      return render_errors([l(:error_sanan_board_pull_no_sprint)])
    end

    status = IssueStatus.find_by(id: params[:status_id])
    return render_errors([l(:error_sanan_board_pull_status, status: '?')]) unless status

    issue.init_journal(User.current)
    attrs = { 'fixed_version_id' => version.id.to_s }
    attrs['status_id'] = status.id.to_s unless status.id == issue.status_id
    sp = team_sp_values(issue)
    return render_errors([l(:error_sanan_board_pull_qa_needs_dev)]) if qa_without_dev?(issue, sp)

    attrs['custom_field_values'] = sp if sp.any?
    issue.safe_attributes = attrs

    if issue.status_id != status.id
      return render_errors([l(:error_sanan_board_pull_status, status: status.name)])
    end
    return render_errors([l(:error_sanan_board_pull_no_sprint)]) if issue.fixed_version_id != version.id

    if issue.save
      render json: { ok: true, issue_id: issue.id, committed: SananAgile::SprintCommit.committed?(issue, @cfg) }
    else
      render_errors(issue.errors.full_messages)
    end
  end

  # A board card dropped on the panel: back to the Product Backlog or into the panel's sprint. Its status is
  # kept; leaving the sprint snapshots and clears its "This sprint" SP (SprintSpHistory), so it is no
  # longer committed there.
  def push
    issue = @project.issues.visible.find_by(id: params[:issue_id])
    return render_errors([l(:error_sanan_board_pull_not_found)], :not_found) unless issue
    return render_errors([l(:error_sanan_board_pull_forbidden)], :forbidden) unless issue.editable?

    source = params[:source].to_s
    issue.init_journal(User.current)
    if source.empty? || source == 'backlog'
      SananAgile::ProductBacklog.assign!(issue, @project, @cfg)
    else
      version = @project.shared_versions.open.find_by(id: source.to_i)
      if version.nil? || SananAgile::BoardBacklog.non_sprint_ids(@cfg).include?(version.id)
        return render_errors([l(:error_sanan_board_pull_no_sprint)])
      end

      issue.fixed_version = version
    end

    if issue.save
      render json: { ok: true, issue_id: issue.id }
    else
      render_errors(issue.errors.full_messages)
    end
  end

  private

  def load_settings
    @cfg = SananAgile::ProjectSettings.load(@project.id)
    render_404 unless @cfg['sanan_agile_enabled'].to_s == '1' && @cfg['agile_board_backlog_enabled'].to_s == '1'
  end

  # { cfid => value } for the parts the popup sent (blank = no SP for that part).
  def team_sp_values(issue)
    raw = params[:sp].respond_to?(:to_unsafe_h) ? params[:sp].to_unsafe_h : (params[:sp] || {})
    allowed = SananAgile::BoardBacklog.sp_parts(issue, @cfg)
    SananAgile::BoardBacklog::TEAM_PARTS.each_with_object({}) do |(part, key), h|
      next unless allowed.include?(part)

      value = raw[part].to_s.strip
      next if value.empty?

      h[@cfg[key].to_i.to_s] = value
    end
  end

  # QA SP alone does not commit a ticket: it needs a BE or FE part (when the ticket can take one).
  def qa_without_dev?(issue, sp)
    parts = SananAgile::BoardBacklog.sp_parts(issue, @cfg)
    cfid = ->(part) { @cfg[SananAgile::BoardBacklog::TEAM_PARTS[part]].to_i.to_s }
    return false unless sp.key?(cfid.call('qa'))
    return false unless parts.include?('be') || parts.include?('fe')

    %w[be fe].none? { |part| sp.key?(cfid.call(part)) }
  end

  def render_errors(messages, status = :unprocessable_entity)
    render json: { ok: false, errors: messages }, status: status
  end
end
