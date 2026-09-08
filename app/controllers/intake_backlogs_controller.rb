# frozen_string_literal: true

# Shared CS / Sale backlog pages (lane set by subclass).
class IntakeBacklogsController < ApplicationController
  unloadable
  before_action :find_project_by_project_id
  before_action :find_project_settings
  before_action :ensure_sanan_agile_enabled
  before_action :ensure_lane_enabled
  before_action :authorize
  before_action :authorize_manage, only: [:create_issue, :quick_update]

  helper :backlogs
  helper :intake_backlogs

  def show
    @lane = lane
    @can_manage = can_manage_lane?
    @can_add_issues = User.current.allowed_to?(:add_issues, @project)
    @filters = {
      tracker_id: params[:tracker_id],
      assigned_to_id: params[:assigned_to_id],
      q: params[:q]
    }
    @data = SananAgile::IntakeBacklogQuery.call(@project, lane: @lane, cfg: @settings, filters: @filters)
    @queue_version = @data[:queue_version]
    @queue_health = SananAgile::IntakeQueueHealth.for_project(@project, cfg: @settings)
    @lane_health = @queue_health.maybe_alert!(@lane)
    @ready_status_ids = Array(@settings["#{@lane}_ready_status_ids"]).map(&:to_i).reject(&:zero?)
    render template: 'intake_backlogs/show'
  end

  def create_issue
    unless User.current.allowed_to?(:add_issues, @project)
      return render_403
    end

    tracker = resolve_tracker
    return redirect_with_error(l(:error_backlog_invalid_tracker)) unless tracker

    queue = queue_version
    return redirect_with_error(l(:error_intake_queue_version_missing)) unless queue

    issue = @project.issues.new(
      tracker: tracker,
      author: User.current,
      subject: params[:subject].to_s.strip,
      fixed_version: queue
    )
    issue.status = issue.default_status if issue.respond_to?(:default_status)
    issue.status ||= IssueStatus.sorted.first
    issue.priority ||= IssuePriority.default || IssuePriority.active.first
    SananAgile::IntakeSource.set!(issue, @settings, lane)

    if issue.subject.blank?
      flash[:error] = l(:error_backlog_subject_blank)
      return redirect_to lane_path
    end

    if issue.save
      flash[:notice] = l(:notice_intake_issue_created, id: issue.id)
    else
      flash[:error] = issue.errors.full_messages.join(', ')
    end
    redirect_to lane_path
  end

  def quick_update
    issue = @project.issues.visible.find(params[:issue_id])
    unless User.current.allowed_to?(:edit_issues, @project)
      return render json: { ok: false, error: 'forbidden' }, status: :forbidden
    end

    unless issue_in_queue?(issue)
      return render json: {
        ok: false,
        error: l(:error_intake_edit_only_queue)
      }, status: :unprocessable_entity
    end

    field = params[:field].to_s
    value = params[:value]
    ok = apply_quick_update!(issue, field, value)
    unless ok
      return render json: {
        ok: false,
        error: issue.errors.full_messages.presence&.join(', ') || l(:notice_failed_to_save_issues)
      }, status: :unprocessable_entity
    end

    issue.reload
    render json: {
      ok: true,
      issue_id: issue.id,
      field: field,
      display: quick_update_display(issue, field)
    }
  end

  private

  def lane
    raise NotImplementedError
  end

  def view_permission
    raise NotImplementedError
  end

  def manage_permission
    raise NotImplementedError
  end

  def enabled_setting_key
    raise NotImplementedError
  end

  def find_project_settings
    @settings = SananAgile::ProjectSettings.load(@project.id) || {}
  end

  def ensure_sanan_agile_enabled
    return if @settings['sanan_agile_enabled'].to_s == '1'

    render_404
  end

  def ensure_lane_enabled
    return if @settings[enabled_setting_key].to_s == '1'

    render_404
  end

  def authorize_manage
    return true if can_manage_lane?

    render_403
  end

  def can_manage_lane?
    User.current.allowed_to?(manage_permission, @project)
  end

  def queue_version
    vid = SananAgile::IntakeSource.queue_version_id(@settings, lane)
    return nil if vid <= 0

    @project.shared_versions.find_by(id: vid)
  end

  def issue_in_queue?(issue)
    qid = SananAgile::IntakeSource.queue_version_id(@settings, lane)
    qid.positive? && issue.fixed_version_id.to_i == qid
  end

  def resolve_tracker
    tid = params[:tracker_id].to_i
    if tid.positive?
      @project.trackers.find_by(id: tid)
    else
      ids = Array(@settings['backlog_trackers']).map(&:to_i).reject(&:zero?)
      ids = Array(@settings['standard_tracker']).map(&:to_i).reject(&:zero?) if ids.blank?
      @project.trackers.find_by(id: ids.first) || @project.trackers.first
    end
  end

  def lane_path
    case lane
    when 'cs' then project_cs_backlog_path(@project)
    when 'sale' then project_sale_backlog_path(@project)
    else project_path(@project)
    end
  end

  def redirect_with_error(msg)
    flash[:error] = msg
    redirect_to lane_path
  end

  def apply_quick_update!(issue, field, value)
    issue.init_journal(User.current, "[#{lane} backlog quick update]")
    case field
    when 'subject'
      issue.subject = value.to_s.strip
      return false if issue.subject.blank?
    when 'tracker_id'
      tracker = @project.trackers.find_by(id: value.to_i)
      return false unless tracker

      issue.tracker = tracker
    when 'priority_id'
      priority = IssuePriority.active.find_by(id: value.to_i)
      return false unless priority

      issue.priority = priority
    when 'status_id'
      status = IssueStatus.find_by(id: value.to_i)
      return false unless status
      return false unless issue.new_statuses_allowed_to(User.current).include?(status)

      issue.status = status
    when 'assigned_to_id'
      if value.blank? || value.to_s == '0'
        issue.assigned_to = nil
      else
        user = @project.assignable_users.detect { |u| u.id == value.to_i }
        return false unless user

        issue.assigned_to = user
      end
    when 'story_points', 'sp'
      return apply_quick_sp!(issue, value)
    else
      return false
    end
    issue.save
  end

  def apply_quick_sp!(issue, value)
    raw = value.to_s.strip.tr(',', '.')
    sp = raw.blank? ? nil : Float(raw)
    cf = @settings['story_point_cfid'].to_i
    if cf > 0
      issue.safe_attributes = { 'custom_field_values' => { cf.to_s => (sp.nil? ? '' : sp.to_s) } }
      issue.save
    else
      row = (defined?(AgileData) ? AgileData : SananAgile::AgileData).find_or_initialize_by(issue_id: issue.id)
      row.story_points = sp
      row.save(validate: false)
    end
  rescue ArgumentError, TypeError
    false
  end

  def quick_update_display(issue, field)
    case field
    when 'subject'
      { text: issue.subject }
    when 'tracker_id'
      { text: issue.tracker.name, id: issue.tracker_id }
    when 'priority_id'
      {
        id: issue.priority_id,
        text: issue.priority&.name.to_s,
        html: view_context.backlog_priority_badge(issue.priority)
      }
    when 'status_id'
      { text: issue.status.name, id: issue.status_id }
    when 'assigned_to_id'
      {
        id: issue.assigned_to_id,
        text: issue.assigned_to ? issue.assigned_to.name : '—',
        html: issue.assigned_to ? view_context.link_to_user(issue.assigned_to) : '—'
      }
    when 'story_points', 'sp'
      sp = SananAgile::IntakeBacklogQuery.new(@project, lane: lane, cfg: @settings).story_point_for(issue)
      { text: (sp == sp.to_i ? sp.to_i : sp.round(2)).to_s }
    else
      {}
    end
  end
end
