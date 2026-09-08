# frozen_string_literal: true

class BacklogsController < ApplicationController
  unloadable
  before_action :find_project_by_project_id
  before_action :find_project_settings
  before_action :ensure_sanan_agile_enabled
  before_action :ensure_backlog_enabled
  before_action :authorize
  before_action :authorize_manage, only: [
    :reorder, :create_sprint, :start_sprint, :complete_sprint,
    :create_issue, :create_epic, :bulk_move, :attach_to_release,
    :bulk_update_status, :bulk_update_priority, :bulk_update_tracker,
    :bulk_destroy, :quick_update
  ]

  helper :backlogs

  def show
    @filters = {
      tracker_id: params[:tracker_id],
      assigned_to_id: params[:assigned_to_id],
      epic_id: params[:epic_id],
      q: params[:q],
      without_release: params[:without_release]
    }
    @data = SananAgile::BacklogQuery.call(@project, cfg: @settings, filters: @filters)
    @can_manage = User.current.allowed_to?(:manage_backlog, @project)
    @can_add_issues = User.current.allowed_to?(:add_issues, @project)
    @can_manage_releases = User.current.allowed_to?(:manage_releases, @project)
    @can_delete_issues = User.current.allowed_to?(:delete_issues, @project)
    @open_versions = @project.shared_versions.open.sort_by { |v| [v.effective_date || Date.new(9999, 1, 1), v.id] }
    @attachable_releases = attachable_releases
    @issue_statuses = IssueStatus.sorted.to_a
    @priorities = IssuePriority.active
    @assignables = @project.assignable_users.sort_by { |u| u.name.to_s.downcase }
    preload_releases!
    annotate_without_release_counts!
  end

  def reorder
    issue = find_editable_issue(params[:issue_id])
    return unless issue

    apply_version!(issue, params[:to_version_id])
    unless issue.save
      return render json: { ok: false, errors: issue.errors.full_messages }, status: :unprocessable_entity
    end

    persist_positions!(params[:positions])
    render json: { ok: true }
  end

  def create_sprint
    unless User.current.allowed_to?(:manage_versions, @project)
      return render_403
    end

    attrs = {
      name: params[:name].to_s.strip,
      description: params[:goal].to_s.strip,
      effective_date: parse_date(params[:effective_date]),
      status: 'open',
      sharing: 'none'
    }
    version = @project.versions.build(attrs)
    start_date = parse_date(params[:start_date])
    version.sanan_sprint_start_date = start_date if start_date

    if version.name.blank?
      flash[:error] = l(:error_backlog_sprint_name_blank)
      return redirect_to project_backlog_path(@project, filter_redirect_params)
    end

    unless version.save
      flash[:error] = version.errors.full_messages.join(', ')
      return redirect_to project_backlog_path(@project, filter_redirect_params)
    end

    version.save_sanan_sprint_start_date!

    ids = Array(params[:issue_ids]).map(&:to_i).reject(&:zero?).uniq
    moved = 0
    if ids.any?
      Issue.where(project_id: @project.id, id: ids).find_each do |issue|
        next unless User.current.allowed_to?(:edit_issues, @project)

        issue.init_journal(User.current, '[backlog create sprint]')
        issue.fixed_version = version
        moved += 1 if issue.save
      end
    end

    flash[:notice] = if moved.positive?
                       l(:notice_backlog_sprint_created_with_issues, name: version.name, count: moved)
                     else
                       l(:notice_backlog_sprint_created, name: version.name)
                     end
    redirect_to project_backlog_path(@project, filter_redirect_params)
  end

  def start_sprint
    version = @project.shared_versions.open.find(params[:version_id])
    unless User.current.allowed_to?(:manage_versions, @project) || User.current.allowed_to?(:edit_project, @project)
      return render_403
    end

    @project.default_version = version
    if @project.save
      flash[:notice] = l(:notice_backlog_sprint_started, name: version.name)
    else
      flash[:error] = @project.errors.full_messages.join(', ')
    end
    redirect_to project_backlog_path(@project)
  end

  def complete_sprint
    version = @project.shared_versions.find(params[:version_id])
    unless User.current.allowed_to?(:manage_versions, @project)
      return render_403
    end

    move_to = params[:move_unfinished_to].to_s
    unfinished = unfinished_issues_for(version)

    case move_to
    when 'backlog'
      unfinished.find_each do |issue|
        next unless User.current.allowed_to?(:edit_issues, @project)

        issue.init_journal(User.current, '[backlog complete sprint]')
        issue.fixed_version = nil
        issue.save
      end
    when /\A\d+\z/
      target = @project.shared_versions.open.find_by(id: move_to)
      if target
        unfinished.find_each do |issue|
          next unless User.current.allowed_to?(:edit_issues, @project)

          issue.init_journal(User.current, '[backlog complete sprint]')
          issue.fixed_version = target
          issue.save
        end
      end
    end

    if @project.default_version_id == version.id
      @project.default_version = nil
      @project.save
    end

    version.status = 'closed'
    if version.save
      flash[:notice] = l(:notice_successful_update)
      if User.current.allowed_to?(:view_sprint_reports, @project)
        redirect_to project_sprint_report_path(@project, version)
      else
        redirect_to project_backlog_path(@project)
      end
    else
      flash[:error] = version.errors.full_messages.join(', ')
      redirect_to project_backlog_path(@project)
    end
  end

  def create_issue
    unless User.current.allowed_to?(:add_issues, @project)
      return render_403
    end

    tracker_ids = backlog_tracker_ids
    tracker = Tracker.find_by(id: params[:tracker_id].to_i) || Tracker.find_by(id: tracker_ids.first)
    return redirect_with_error(l(:error_backlog_no_tracker)) unless tracker && tracker_ids.include?(tracker.id)

    issue = @project.issues.new(
      tracker: tracker,
      author: User.current,
      subject: params[:subject].to_s.strip
    )
    issue.status = issue.default_status if issue.respond_to?(:default_status)
    issue.status ||= IssueStatus.sorted.first
    issue.priority ||= IssuePriority.default || IssuePriority.active.first

    if params[:version_id].present?
      issue.fixed_version = @project.shared_versions.open.find_by(id: params[:version_id])
    end
    if params[:parent_id].present?
      issue.parent_issue_id = params[:parent_id]
    end

    if issue.subject.blank?
      flash[:error] = l(:error_backlog_subject_blank)
      return redirect_to project_backlog_path(@project, filter_redirect_params)
    end

    if issue.save
      flash[:notice] = l(:notice_successful_create)
    else
      flash[:error] = issue.errors.full_messages.join(', ')
    end
    redirect_to project_backlog_path(@project, filter_redirect_params)
  end

  def create_epic
    unless User.current.allowed_to?(:add_issues, @project)
      return render_403
    end

    epic_tracker = Tracker.find_by(id: @settings['epic_tracker'].to_i)
    return redirect_with_error(l(:error_backlog_no_epic_tracker)) unless epic_tracker

    issue = @project.issues.new(
      tracker: epic_tracker,
      author: User.current,
      subject: params[:subject].to_s.strip
    )
    issue.status = issue.default_status if issue.respond_to?(:default_status)
    issue.status ||= IssueStatus.sorted.first
    issue.priority ||= IssuePriority.default || IssuePriority.active.first

    if issue.subject.blank?
      flash[:error] = l(:error_backlog_subject_blank)
      return redirect_to project_backlog_path(@project, filter_redirect_params)
    end

    if issue.save
      flash[:notice] = l(:notice_backlog_epic_created, name: issue.subject)
      redirect_to project_backlog_path(@project, filter_redirect_params.merge(epic_id: issue.id))
    else
      flash[:error] = issue.errors.full_messages.join(', ')
      redirect_to project_backlog_path(@project, filter_redirect_params)
    end
  end

  def bulk_move
    ids = Array(params[:issue_ids]).map(&:to_i).reject(&:zero?)
    return redirect_with_error(l(:error_backlog_no_issues)) if ids.blank?

    to_version_id = params[:to_version_id].presence
    version = nil
    if to_version_id
      version = @project.shared_versions.open.find_by(id: to_version_id)
      return redirect_with_error(l(:error_backlog_invalid_version)) unless version
    end

    count = 0
    Issue.where(project_id: @project.id, id: ids).find_each do |issue|
      next unless User.current.allowed_to?(:edit_issues, @project)

      issue.init_journal(User.current)
      issue.fixed_version = version
      count += 1 if issue.save
    end
    flash[:notice] = l(:notice_backlog_bulk_moved, count: count)
    redirect_to project_backlog_path(@project, filter_redirect_params)
  end

  def attach_to_release
    unless User.current.allowed_to?(:manage_releases, @project)
      return render_403
    end

    ids = Array(params[:issue_ids]).map(&:to_i).reject(&:zero?)
    return redirect_with_error(l(:error_backlog_no_issues)) if ids.blank?

    release = ReleaseVersion.where(project_id: @project.id).find_by(id: params[:release_id].to_i)
    return redirect_with_error(l(:error_backlog_invalid_release)) unless release
    if release.state.to_s == 'archived'
      return redirect_with_error(l(:error_backlog_invalid_release))
    end

    count = 0
    ReleaseItem.transaction do
      Issue.where(project_id: @project.id, id: ids).find_each do |issue|
        ri = ReleaseItem.find_or_initialize_by(issue_id: issue.id)
        ri.release_version_id = release.id
        ri.added_at ||= Time.current
        ri.added_by_id ||= User.current.id
        count += 1 if ri.save
      end
    end
    flash[:notice] = l(:notice_backlog_attached_to_release, count: count, name: release.name)
    redirect_to project_backlog_path(@project, filter_redirect_params)
  end

  def bulk_update_status
    ids = Array(params[:issue_ids]).map(&:to_i).reject(&:zero?)
    return redirect_with_error(l(:error_backlog_no_issues)) if ids.blank?

    status = IssueStatus.find_by(id: params[:status_id].to_i)
    return redirect_with_error(l(:error_backlog_invalid_status)) unless status

    count = 0
    skipped = 0
    Issue.where(project_id: @project.id, id: ids).find_each do |issue|
      unless User.current.allowed_to?(:edit_issues, @project)
        skipped += 1
        next
      end
      allowed = issue.new_statuses_allowed_to(User.current)
      unless allowed.include?(status)
        skipped += 1
        next
      end

      issue.init_journal(User.current, '[backlog bulk status]')
      issue.status = status
      if issue.save
        count += 1
      else
        skipped += 1
      end
    end

    flash[:notice] = l(:notice_backlog_bulk_status, count: count, name: status.name)
    flash[:warning] = l(:warning_backlog_bulk_skipped, count: skipped) if skipped > 0
    redirect_to project_backlog_path(@project, filter_redirect_params)
  end

  def bulk_update_priority
    ids = Array(params[:issue_ids]).map(&:to_i).reject(&:zero?)
    return redirect_with_error(l(:error_backlog_no_issues)) if ids.blank?

    priority = IssuePriority.active.find_by(id: params[:priority_id].to_i)
    return redirect_with_error(l(:error_backlog_invalid_priority)) unless priority

    count, skipped = bulk_assign_attribute(ids, '[backlog bulk priority]') do |issue|
      issue.priority = priority
    end

    flash[:notice] = l(:notice_backlog_bulk_priority, count: count, name: priority.name)
    flash[:warning] = l(:warning_backlog_bulk_skipped, count: skipped) if skipped > 0
    redirect_to project_backlog_path(@project, filter_redirect_params)
  end

  def bulk_update_tracker
    ids = Array(params[:issue_ids]).map(&:to_i).reject(&:zero?)
    return redirect_with_error(l(:error_backlog_no_issues)) if ids.blank?

    tracker = @project.trackers.find_by(id: params[:tracker_id].to_i)
    return redirect_with_error(l(:error_backlog_invalid_tracker)) unless tracker

    count, skipped = bulk_assign_attribute(ids, '[backlog bulk tracker]') do |issue|
      issue.tracker = tracker
    end

    flash[:notice] = l(:notice_backlog_bulk_tracker, count: count, name: tracker.name)
    flash[:warning] = l(:warning_backlog_bulk_skipped, count: skipped) if skipped > 0
    redirect_to project_backlog_path(@project, filter_redirect_params)
  end

  def quick_update
    issue = find_editable_issue(params[:issue_id])
    return unless issue

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

  def bulk_destroy
    unless User.current.allowed_to?(:delete_issues, @project)
      return render_403
    end

    ids = Array(params[:issue_ids]).map(&:to_i).reject(&:zero?)
    return redirect_with_error(l(:error_backlog_no_issues)) if ids.blank?

    count = 0
    Issue.where(project_id: @project.id, id: ids).find_each do |issue|
      next unless issue.respond_to?(:deletable?) ? issue.deletable? : true

      issue.destroy
      count += 1
    end
    flash[:notice] = l(:notice_backlog_bulk_deleted, count: count)
    redirect_to project_backlog_path(@project, filter_redirect_params)
  end

  private

  def filter_redirect_params
    params.permit(:epic_id, :tracker_id, :q, :assigned_to_id, :without_release).to_h
  end

  def attachable_releases
    return [] unless defined?(ReleaseVersion)

    ReleaseVersion.where(project_id: @project.id)
                  .where.not(state: 'archived')
                  .order(:name)
  end

  # When filter is off, count issues lacking a release per section (for header hints).
  def annotate_without_release_counts!
    sections = []
    sections << @data[:active] if @data[:active]
    sections.concat(@data[:future])
    sections << @data[:backlog]
    sections.compact.each do |section|
      section.define_singleton_method(:without_release_count) do
        @without_release_count ||= section.issues.count { |i| ReleaseVersion.for_issue(i).nil? }
      end
    end
  end

  def bulk_assign_attribute(ids, journal_note)
    count = 0
    skipped = 0
    Issue.where(project_id: @project.id, id: ids).find_each do |issue|
      unless User.current.allowed_to?(:edit_issues, @project)
        skipped += 1
        next
      end
      issue.init_journal(User.current, journal_note)
      yield issue
      if issue.save
        count += 1
      else
        skipped += 1
      end
    end
    [count, skipped]
  end

  def apply_quick_update!(issue, field, value)
    issue.init_journal(User.current, '[backlog quick update]')
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
    when 'parent_id', 'epic_id'
      if value.blank? || value.to_s == '0'
        issue.parent_issue_id = nil
      else
        epic_tracker = @settings['epic_tracker'].to_i
        epic = @project.issues.find_by(id: value.to_i)
        return false unless epic
        return false if epic_tracker > 0 && epic.tracker_id != epic_tracker

        issue.parent_issue_id = epic.id
      end
    when 'release_id'
      return apply_quick_release!(issue, value)
    when 'story_points', 'sp'
      return apply_quick_sp!(issue, value)
    else
      return false
    end
    issue.save
  end

  def apply_quick_release!(issue, value)
    return false unless defined?(ReleaseVersion) && defined?(ReleaseItem)
    return false unless User.current.allowed_to?(:manage_releases, @project)

    if value.blank? || value.to_s == '0'
      ReleaseItem.where(issue_id: issue.id).delete_all
      return true
    end

    release = ReleaseVersion.where(project_id: @project.id).find_by(id: value.to_i)
    return false unless release
    return false if release.state.to_s == 'archived'

    ri = ReleaseItem.find_or_initialize_by(issue_id: issue.id)
    ri.release_version_id = release.id
    ri.added_at ||= Time.current
    ri.added_by_id ||= User.current.id
    ri.save
  end

  def apply_quick_sp!(issue, value)
    raw = value.to_s.strip.tr(',', '.')
    sp = raw.blank? ? nil : Float(raw)
    cf = @settings['story_point_cfid'].to_i
    if cf > 0
      issue.safe_attributes = { 'custom_field_values' => { cf.to_s => (sp.nil? ? '' : sp.to_s) } }
      return false unless issue.save

      # IssuePatch syncs CF → agile_data
      true
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
    when 'parent_id', 'epic_id'
      epic_tid = @settings['epic_tracker'].to_i
      label = view_context.backlog_epic_label(issue, epic_tid)
      text = label.presence || '—'
      { id: issue.parent_id.to_i, text: text, html: ERB::Util.html_escape(text) }
    when 'release_id'
      badge = view_context.backlog_release_badge(issue)
      rel = defined?(ReleaseVersion) ? ReleaseVersion.for_issue(issue) : nil
      { id: rel&.id, text: rel&.name || '—', html: badge || '—' }
    when 'story_points', 'sp'
      { text: view_context.backlog_issue_sp(issue).to_s }
    else
      {}
    end
  end

  def find_project_settings
    @settings = SananAgile::ProjectSettings.load(@project.id) || {}
  end

  def ensure_sanan_agile_enabled
    return if @settings['sanan_agile_enabled'].to_s == '1'

    render_404
  end

  def ensure_backlog_enabled
    return if @settings['backlog_enabled'].to_s != '0'

    render_404
  end

  def authorize_manage
    return true if User.current.allowed_to?(:manage_backlog, @project)

    render_403
  end

  def find_editable_issue(id)
    issue = @project.issues.visible.find(id)
    unless User.current.allowed_to?(:edit_issues, @project)
      render json: { ok: false, error: 'forbidden' }, status: :forbidden
      return nil
    end
    issue
  end

  def apply_version!(issue, to_version_id)
    issue.init_journal(User.current)
    if to_version_id.present?
      version = @project.shared_versions.open.find_by(id: to_version_id)
      raise ActiveRecord::RecordNotFound unless version

      issue.fixed_version = version
    else
      issue.fixed_version = nil
    end
  end

  def persist_positions!(positions)
    return if positions.blank?

    AgileData.transaction do
      Issue.eager_load(:agile_data).where(id: positions.keys, project_id: @project.id).find_each do |iss|
        pos = positions[iss.id.to_s]
        next unless pos

        iss.agile_data.position = pos['position'].presence || pos[:position]
        iss.agile_data.save
      end
    end
  end

  def unfinished_issues_for(version)
    closed_ids = IssueStatus.where(is_closed: true).pluck(:id)
    scope = Issue.where(project_id: @project.id, fixed_version_id: version.id)
    scope = scope.where.not(status_id: closed_ids) if closed_ids.any?
    scope
  end

  def backlog_tracker_ids
    ids = Array(@settings['backlog_trackers']).map(&:to_i).reject(&:zero?)
    ids = Array(@settings['standard_tracker']).map(&:to_i).reject(&:zero?) if ids.blank?
    ids
  end

  def parse_date(val)
    return nil if val.blank?

    Date.parse(val.to_s)
  rescue ArgumentError
    nil
  end

  def redirect_with_error(msg)
    flash[:error] = msg
    redirect_to project_backlog_path(@project)
  end

  def preload_releases!
    issues = []
    issues.concat(@data[:active].issues) if @data[:active]
    @data[:future].each { |s| issues.concat(s.issues) }
    issues.concat(@data[:backlog].issues)
    ReleaseVersion.preload_for_issues!(issues) if issues.any? && defined?(ReleaseVersion)
  end
end
