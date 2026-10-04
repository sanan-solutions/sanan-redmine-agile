# frozen_string_literal: true

class BacklogsController < ApplicationController
  unloadable
  before_action :find_project_by_project_id
  before_action :find_project_settings
  before_action :ensure_sanan_agile_enabled
  before_action :ensure_backlog_enabled
  before_action :authorize
  before_action :authorize_manage, only: [
    :reorder, :create_sprint, :update_sprint, :destroy_sprint, :start_sprint, :complete_sprint,
    :create_issue, :create_epic, :bulk_move, :attach_to_release,
    :bulk_update_status, :bulk_update_priority, :bulk_update_tracker,
    :bulk_destroy, :quick_update, :pull_intake, :update_sprint_quota
  ]

  helper :backlogs

  def show
    assign_backlog_filters
    load_backlog_board!
    load_intake_alerts!
  end

  def sections
    assign_backlog_filters
    load_backlog_board!
    render partial: 'sections', layout: false
  end

  def issues
    assign_backlog_filters
    @can_manage = User.current.allowed_to?(:manage_backlog, @project)
    query = SananAgile::BacklogQuery.new(@project, cfg: @settings, filters: @filters)
    offset = [params[:offset].to_i, 0].max
    page = query.backlog_page(offset: offset, compute_sp: false)
    @issues = page[:issues]
    ReleaseVersion.preload_for_issues!(@issues) if @issues.any? && defined?(ReleaseVersion)
    html = render_to_string(
      partial: 'issue_rows',
      locals: { issues: @issues, row_offset: offset }
    )
    if page[:has_more]
      html += render_to_string(
        partial: 'load_more_row',
        locals: {
          next_offset: page[:next_offset],
          loaded: page[:loaded],
          total: page[:total]
        }
      )
    end
    render json: {
      html: html,
      next_offset: page[:next_offset],
      has_more: page[:has_more],
      loaded: page[:loaded],
      total: page[:total]
    }
  end

  def reorder
    issue = find_editable_issue(params[:issue_id])
    return unless issue

    apply_version!(issue, params[:to_version_id])
    unless issue.save
      return render json: { ok: false, error: issue.errors.full_messages.first, errors: issue.errors.full_messages },
                    status: :unprocessable_entity
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
    version.sanan_cs_quota_sp = params[:cs_quota_sp].presence || @settings['default_cs_quota_sp']
    version.sanan_sale_quota_sp = params[:sale_quota_sp].presence || @settings['default_sale_quota_sp']
    apply_sprint_commit_sp!(version)

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

  def update_sprint
    unless User.current.allowed_to?(:manage_versions, @project)
      return render_403
    end

    version = @project.versions.find(params[:version_id])
    version.name = params[:name].to_s.strip
    version.description = params[:goal].to_s.strip
    version.effective_date = parse_date(params[:effective_date])
    start_date = parse_date(params[:start_date])
    version.sanan_sprint_start_date = start_date
    version.sanan_cs_quota_sp = params[:cs_quota_sp] if params.key?(:cs_quota_sp)
    version.sanan_sale_quota_sp = params[:sale_quota_sp] if params.key?(:sale_quota_sp)
    apply_sprint_commit_sp!(version)

    if version.name.blank?
      flash[:error] = l(:error_backlog_sprint_name_blank)
      return redirect_to project_backlog_path(@project, filter_redirect_params)
    end

    if version.save
      version.save_sanan_sprint_start_date!
      flash[:notice] = l(:notice_backlog_sprint_updated, name: version.name)
    else
      flash[:error] = version.errors.full_messages.join(', ')
    end
    redirect_to project_backlog_path(@project, filter_redirect_params)
  end

  def destroy_sprint
    unless User.current.allowed_to?(:manage_versions, @project)
      return render_403
    end

    version = @project.versions.find(params[:version_id])
    name = version.name

    if @project.default_version_id == version.id
      @project.default_version = nil
      @project.save
    end

    Issue.where(project_id: @project.id, fixed_version_id: version.id).find_each do |issue|
      next unless User.current.allowed_to?(:edit_issues, @project)

      issue.init_journal(User.current, '[backlog delete sprint]')
      SananAgile::ProductBacklog.assign!(issue, @project, @settings)
      issue.save
    end

    if version.destroy
      flash[:notice] = l(:notice_backlog_sprint_deleted, name: name)
    else
      flash[:error] = version.errors.full_messages.join(', ')
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

    apply_complete_dod!(version)
    apply_sprint_goal_met!(version)

    if @project.default_version_id == version.id
      @project.default_version = nil
      @project.save
    end

    version.status = 'closed'
    unless version.save
      flash[:error] = version.errors.full_messages.join(', ')
      return redirect_to project_backlog_path(@project)
    end

    move_unfinished_after_complete!(version, params[:move_unfinished_to].to_s)
    flash[:notice] = l(:notice_successful_update)
    if User.current.allowed_to?(:view_sprint_reports, @project)
      redirect_to project_sprint_report_path(@project, version)
    else
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
    else
      SananAgile::ProductBacklog.assign!(issue, @project, @settings)
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
    blocked = 0
    Issue.where(project_id: @project.id, id: ids).find_each do |issue|
      next unless User.current.allowed_to?(:edit_issues, @project)

      issue.init_journal(User.current)
      if version
        issue.fixed_version = version
      else
        SananAgile::ProductBacklog.assign!(issue, @project, @settings)
      end
      if issue.save
        count += 1
      elsif issue.errors[:base].any?
        blocked += 1
      end
    end
    flash[:error] = l(:error_sanan_commit_locked) if blocked.positive?
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

  def pull_intake
    lane = params[:source].to_s
    unless %w[cs sale].include?(lane)
      return redirect_with_error(l(:error_intake_invalid_source))
    end

    to_version = nil
    if params[:to_version_id].present?
      to_version = @project.shared_versions.open.find_by(id: params[:to_version_id].to_i)
      queue_ids = SananAgile::IntakeSource.intake_queue_version_ids(@settings)
      if to_version.nil? || queue_ids.include?(to_version.id)
        return redirect_with_error(l(:error_backlog_invalid_version))
      end
    end

    result = SananAgile::IntakePull.call(
      project: @project,
      cfg: @settings,
      lane: lane,
      issue_ids: params[:issue_ids],
      to_version: to_version,
      user: User.current
    )

    unless result.ok
      flash[:error] = intake_pull_error_message(result)
      return redirect_to project_backlog_path(@project, filter_redirect_params)
    end

    flash[:notice] = l(:notice_intake_pulled, count: result.pulled, source: lane.upcase)
    if result.skipped.to_i.positive?
      flash[:warning] = l(:warning_backlog_bulk_skipped, count: result.skipped)
    end
    redirect_to project_backlog_path(@project, filter_redirect_params)
  end

  def update_sprint_quota
    version = @project.shared_versions.find_by(id: params[:version_id].to_i)
    return redirect_with_error(l(:error_backlog_invalid_version)) unless version

    version.sanan_cs_quota_sp = params[:cs_quota_sp]
    version.sanan_sale_quota_sp = params[:sale_quota_sp]
    if version.save_sanan_sprint_start_date!
      flash[:notice] = l(:notice_intake_quota_updated, name: version.name)
    else
      flash[:error] = version.sanan_agile_version_meta&.errors&.full_messages&.join(', ') ||
                      l(:notice_failed_to_save_issues)
    end
    redirect_to project_backlog_path(@project, filter_redirect_params)
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

  def assign_backlog_filters
    @filters = {
      tracker_id: params[:tracker_id],
      assigned_to_id: params[:assigned_to_id],
      epic_id: params[:epic_id],
      q: params[:q],
      without_release: params[:without_release]
    }
  end

  def load_backlog_board!
    @data = SananAgile::BacklogQuery.call(@project, cfg: @settings, filters: @filters)
    @can_manage = User.current.allowed_to?(:manage_backlog, @project)
    @can_add_issues = User.current.allowed_to?(:add_issues, @project)
    @can_manage_releases = User.current.allowed_to?(:manage_releases, @project)
    @can_delete_issues = User.current.allowed_to?(:delete_issues, @project)
    queue_ids = SananAgile::IntakeSource.intake_queue_version_ids(@settings)
    backlog_version_ids = SananAgile::ProductBacklog.version_ids(@settings)
    @open_versions = @project.shared_versions.open
                             .reject { |v| queue_ids.include?(v.id) || backlog_version_ids.include?(v.id) }
                             .sort_by { |v| [v.effective_date || Date.new(9999, 1, 1), v.id] }
    @attachable_releases = attachable_releases
    @issue_statuses = IssueStatus.sorted.to_a
    @priorities = IssuePriority.active
    @assignables = @project.assignable_users.sort_by { |u| u.name.to_s.downcase }
    @intake = SananAgile::IntakeCandidates.for_project(@project, cfg: @settings)
    @velocity = SananAgile::Velocity.call(@project, cfg: @settings)
    @intake_quota_by_version = {}
    ([@data[:active]] + Array(@data[:future])).compact.each do |section|
      next unless section.version

      @intake_quota_by_version[section.version.id] =
        SananAgile::IntakeCandidates.new(@project, cfg: @settings).quota_stats_for(section.version)
    end
    preload_releases!
    annotate_without_release_counts!
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
      next unless section.version

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
    return if @settings['backlog_enabled'].to_s == '1'

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
      SananAgile::ProductBacklog.assign!(issue, @project, @settings)
    end
  end

  def persist_positions!(positions)
    return if positions.blank?

    AgileData.transaction do
      Issue.where(id: positions.keys, project_id: @project.id).find_each do |iss|
        pos = positions[iss.id.to_s]
        next unless pos

        row = AgileData.find_or_initialize_by(issue_id: iss.id)
        row.position = pos['position'].presence || pos[:position]
        row.save
      end
    end
  end

  def apply_sprint_commit_sp!(version)
    values = {}
    {
      commit_sp: 'sp_commit_version_cfid',
      commit_sp_be: 'sp_be_commit_version_cfid',
      commit_sp_fe: 'sp_fe_commit_version_cfid',
      commit_sp_qa: 'sp_qa_commit_version_cfid'
    }.each do |param_key, setting_key|
      cfid = @settings[setting_key].to_i
      next if cfid <= 0
      next unless params.key?(param_key)

      values[cfid.to_s] = params[param_key].to_s.strip
    end
    version.custom_field_values = values if values.any?
  end

  def unfinished_issues_for(version)
    closed_ids = IssueStatus.where(is_closed: true).pluck(:id)
    scope = Issue.where(project_id: @project.id, fixed_version_id: version.id)
    scope = scope.where.not(status_id: closed_ids) if closed_ids.any?
    scope
  end

  def complete_dod_eligible_ids(version)
    status_ids = Array(@settings['dod_checkbox_statuses']).map(&:to_i).reject(&:zero?)
    return [] if status_ids.empty?

    scope = Issue.where(project_id: @project.id, fixed_version_id: version.id, status_id: status_ids)
    tracker_ids = Array(@settings['dod_checkbox_trackers']).map(&:to_i).reject(&:zero?)
    scope = scope.where(tracker_id: tracker_ids) if tracker_ids.any?
    scope.pluck(:id)
  end

  def apply_complete_dod!(version)
    return [] unless params[:dod_confirmed].present?

    eligible = complete_dod_eligible_ids(version)
    selected = Array(params[:dod_issue_ids]).map(&:to_i) & eligible
    dod_cfid = @settings['dod_cfid'].to_i
    return selected if dod_cfid <= 0 || eligible.empty?

    cf = IssueCustomField.find_by(id: dod_cfid)
    return selected unless cf

    val = cf.field_format == 'version' ? version.id.to_s : version.name.to_s
    match_vals = [version.id.to_s, version.name.to_s].uniq
    Issue.where(id: eligible).find_each do |issue|
      next unless User.current.allowed_to?(:edit_issues, @project)

      current = Array(issue.custom_field_value(dod_cfid)).map { |v| v.to_s.strip }
      want = selected.include?(issue.id)
      already = (current & match_vals).any?
      next if want == already

      issue.init_journal(User.current, "[backlog complete sprint] DoD #{want ? 'set' : 'clear'}")
      issue.safe_attributes = { 'custom_field_values' => { dod_cfid.to_s => (want ? val : '') } }
      issue.save(validate: false)
    end
    selected
  end

  def apply_sprint_goal_met!(version)
    allowed = SananAgileVersionMeta::GOAL_MET_VALUES
    val = params[:goal_met].to_s
    val = 'unreviewed' unless allowed.include?(val)
    meta = version.sanan_agile_version_meta || version.build_sanan_agile_version_meta
    meta.goal_met = val
    meta.goal_note = params[:goal_note].to_s.strip.presence
    meta.version_id = version.id
    meta.save
  end

  # Every open ticket moves on, DoD-reached ones included (e.g. waiting for UAT): the DoD field already
  # records the sprint where DoD was reached. Moving snapshots this sprint's team SP and clears it.
  def move_unfinished_after_complete!(version, move_to)
    unfinished = unfinished_issues_for(version)

    case move_to
    when 'backlog'
      unfinished.find_each do |issue|
        next unless User.current.allowed_to?(:edit_issues, @project)

        issue.sanan_skip_commit_lock = true
        issue.init_journal(User.current, '[backlog complete sprint]')
        SananAgile::ProductBacklog.assign!(issue, @project, @settings)
        issue.save
      end
    when /\A\d+\z/
      target = @project.shared_versions.open.find_by(id: move_to)
      return unless target

      unfinished.find_each do |issue|
        next unless User.current.allowed_to?(:edit_issues, @project)

        issue.sanan_skip_commit_lock = true
        issue.init_journal(User.current, '[backlog complete sprint]')
        issue.fixed_version = target
        issue.save
      end
    end
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

  def intake_pull_error_message(result)
    case result.error
    when 'invalid_lane', 'invalid_source'
      l(:error_intake_invalid_source)
    when 'no_issues'
      l(:error_backlog_no_issues)
    when 'queue_missing'
      l(:error_intake_queue_version_missing)
    when 'invalid_candidates'
      ids = Array(result.details && result.details[:not_ready]).presence ||
            Array(result.details && result.details[:not_in_queue])
      l(:error_intake_invalid_candidates, ids: ids.join(', '))
    when 'quota_exceeded'
      d = result.details || {}
      l(:error_intake_quota_exceeded,
        quota: format_sp(d[:quota]),
        used: format_sp(d[:used]),
        adding: format_sp(d[:adding]),
        remaining: format_sp(d[:remaining]))
    else
      l(:notice_failed_to_save_issues)
    end
  end

  def format_sp(n)
    f = n.to_f
    f == f.to_i ? f.to_i : f.round(2)
  end

  def preload_releases!
    issues = []
    issues.concat(@data[:active].issues) if @data[:active]
    @data[:future].each { |s| issues.concat(s.issues) }
    issues.concat(@data[:backlog].issues)
    ReleaseVersion.preload_for_issues!(issues) if issues.any? && defined?(ReleaseVersion)
  end

  def load_intake_alerts!
    @intake_alerts = []
    return unless @intake

    health = SananAgile::IntakeQueueHealth.for_project(@project, cfg: @settings)
    %w[cs sale].each do |lane|
      next unless @intake[:"#{lane}_enabled"]

      h = health.maybe_alert!(lane)
      next unless h.over_threshold || h.over_sla_count.positive?

      @intake_alerts << h
    end
  end
end
