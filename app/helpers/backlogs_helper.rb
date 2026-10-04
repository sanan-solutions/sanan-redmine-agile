# frozen_string_literal: true

module BacklogsHelper
  def backlog_sp_number(n)
    f = n.to_f
    f == f.to_i ? f.to_i : f.round(2)
  end

  def backlog_priority_badge(priority)
    return content_tag(:span, '—') unless priority

    key = backlog_priority_icon_key(priority)
    icon = content_tag(:div, '',
                       class: "priority priority-#{key}",
                       title: "Priority: #{priority.name}")
    content_tag(:span, icon + h(priority.name), class: 'sanan-agile-priority backlog-priority-badge')
  end

  def backlog_priority_icon_key(priority)
    return 'default' unless priority

    name_key = priority.name.to_s
    by_name = {
      'Low' => 'lowest',
      'Normal' => 'default',
      'High' => 'high3',
      'Urgent' => 'high2',
      'Immediate' => 'highest'
    }
    return by_name[name_key] if by_name[name_key]

    pn = priority.respond_to?(:position_name) ? priority.position_name.to_s : ''
    case pn
    when 'highest' then 'highest'
    when 'high2' then 'high2'
    when 'high3', 'high' then 'high3'
    when 'high4' then 'high4'
    when 'high5' then 'high5'
    when 'default' then 'default'
    when 'low3' then 'low3'
    when 'low2' then 'low2'
    when 'lowest' then 'lowest'
    else 'default'
    end
  end

  def backlog_epic_label(issue, epic_tracker_id)
    return nil if epic_tracker_id.to_i <= 0
    return nil unless issue.parent
    return nil unless issue.parent.tracker_id == epic_tracker_id.to_i

    "##{issue.parent.id} #{issue.parent.subject}"
  end

  def backlog_epic_stat(stats, epic_id)
    raw = (stats || {})[epic_id] || (stats || {})[epic_id.to_s] || {}
    {
      count: raw[:count] || raw['count'] || 0,
      closed: raw[:closed] || raw['closed'] || 0,
      progress: raw[:progress] || raw['progress'] || 0
    }
  end

  def backlog_col_count
    @can_manage ? 11 : 10
  end

  def backlog_epic_tracker_id
    (@settings || {})['epic_tracker'].to_i
  end

  def backlog_section_issue_count(section)
    section.issue_count || Array(section.issues).size
  end

  def backlog_section_title(section)
    if section.version.nil?
      l(:label_backlog_unscheduled)
    elsif section.active
      "#{l(:label_backlog_active_sprint)}: #{section.version.name}"
    else
      "#{l(:label_backlog_future_sprint)}: #{section.version.name}"
    end
  end

  def backlog_version_meta(version)
    return '' unless version

    parts = []
    start_on = version.respond_to?(:sanan_sprint_start_date) ? version.sanan_sprint_start_date : nil
    if start_on && version.effective_date
      parts << "#{format_date(start_on)} – #{format_date(version.effective_date)}"
    elsif start_on
      parts << "#{l(:field_start_date)}: #{format_date(start_on)}"
    elsif version.effective_date
      parts << "#{l(:field_effective_date)}: #{format_date(version.effective_date)}"
    end
    parts << (l("version_status_#{version.status}") rescue version.status)
    if version.status.to_s == 'open' && @settings
      cfg = @settings
      cut = SananAgile::CommitLock.cutoff_on(version, cfg)
      if cut
        if SananAgile::CommitLock.locked?(version, cfg)
          parts << l(:label_sanan_commit_locked)
        else
          parts << l(:label_sanan_commit_lock_until, date: format_date(cut))
        end
      end
    end
    parts.compact.join(' · ')
  end

  def backlog_issue_sp(issue, cfg = nil)
    cfg ||= @settings || SananAgile::ProjectSettings.load(@project.id)
    cf = cfg['story_point_cfid'].to_i
    if cf <= 0
      return backlog_sp_number(issue.agile_data&.story_points)
    end

    cv = issue.custom_value_for(cf)
    backlog_sp_number(cv&.value.to_s.strip.empty? ? 0 : cv.value)
  end

  def backlog_release_badge(issue)
    return nil unless defined?(ReleaseVersion)

    release = ReleaseVersion.for_issue(issue)
    return nil unless release

    link_to h(release.name), project_release_path(@project, release),
            class: "backlog-release-badge state-#{release.state}"
  rescue
    nil
  end

  def backlog_intake_source_badge(issue, cfg = nil)
    cfg ||= @settings || SananAgile::ProjectSettings.load(@project.id)
    src = SananAgile::IntakeSource.value_for(issue, cfg)
    return nil unless %w[cs sale].include?(src)

    label = src == 'sale' ? l(:label_intake_source_sale) : l(:label_intake_source_cs)
    content_tag(:span, label, class: "backlog-intake-badge backlog-intake-badge--#{src}", title: label)
  end

  def backlog_commit_sp_chips(section)
    rows = backlog_sp_chip_rows(section)
    return ''.html_safe if rows.empty?

    total = rows.find { |r| r[:role] == 'total' } || rows.first
    teams = rows.reject { |r| r.equal?(total) }
    summary_chip = backlog_sp_chip(
      total[:short],
      total[:commit],
      total[:velocity],
      role: total[:role],
      compact: true
    )
    if teams.empty?
      return content_tag(:span, summary_chip, class: 'backlog-commit-sp', data: { no_toggle: true })
    end

    panel_rows = teams.map do |row|
      tone = backlog_velocity_tone(row[:commit], row[:velocity])
      content_tag(:div, class: "backlog-sp-summary__row#{tone ? " is-#{tone}" : ''}") do
        content_tag(:span, row[:short], class: 'backlog-sp-summary__role') +
          content_tag(:span, backlog_sp_pair(row[:commit], row[:velocity]), class: 'backlog-sp-summary__nums')
      end
    end
    panel = content_tag(:div, safe_join(panel_rows), class: 'backlog-sp-summary__panel', role: 'group')
    caret = content_tag(:span, '▾', class: 'backlog-sp-summary__caret', 'aria-hidden': true)
    tone = backlog_velocity_tone(total[:commit], total[:velocity])
    summary_title = if total[:velocity]
                      l(:title_backlog_commit_vs_velocity,
                        commit: backlog_sp_number(total[:commit]),
                        velocity: backlog_sp_number(total[:velocity]))
                    else
                      "#{l(:label_sprint_report_commit)} #{backlog_sp_number(total[:commit])}"
                    end
    summary = content_tag(:summary, {
      class: ['backlog-sp-chip', 'backlog-sp-chip--total', 'backlog-sp-summary__btn', (tone ? "is-#{tone}" : nil)].compact.join(' '),
      title: summary_title
    }) do
      content_tag(:span, 'SP', class: 'backlog-sp-chip__unit') +
        content_tag(:span, backlog_sp_pair(total[:commit], total[:velocity]), class: 'backlog-sp-chip__nums') +
        caret
    end
    content_tag(:details, summary + panel, class: 'backlog-sp-summary backlog-commit-sp', data: { no_toggle: true })
  end

  def backlog_sp_chip_rows(section)
    cfg = @settings || {}
    velocity = defined?(@velocity) ? @velocity : nil
    compare = section.version.present? && velocity && velocity.sample_size.to_i.positive?
    rows = []
    if cfg['story_point_cfid'].to_i.positive?
      rows << { role: 'total', short: l(:label_backlog_sp_total), commit: section.sp_total, velocity: compare ? velocity.sp : nil }
    end
    if cfg['sp_be_cfid'].to_i.positive?
      rows << { role: 'be', short: l(:label_backlog_sp_be_short), commit: section.sp_be, velocity: compare ? velocity.be : nil }
    end
    if cfg['sp_fe_cfid'].to_i.positive?
      rows << { role: 'fe', short: l(:label_backlog_sp_fe_short), commit: section.sp_fe, velocity: compare ? velocity.fe : nil }
    end
    if cfg['sp_qa_cfid'].to_i.positive?
      rows << { role: 'qa', short: l(:label_backlog_sp_qa_short), commit: section.sp_qa, velocity: compare ? velocity.qa : nil }
    end
    rows
  end

  def backlog_sp_pair(commit, velocity)
    text = backlog_sp_number(commit).to_s
    text += " / #{backlog_sp_number(velocity)}" if velocity
    text
  end

  def backlog_sp_chip(label, commit, velocity, role:, compact: false)
    pair = backlog_sp_pair(commit, velocity)
    text = if compact && role.to_s == 'total'
             "#{l(:label_backlog_sp_total)} #{pair}"
           elsif compact
             "#{label} #{pair}"
           elsif velocity
             "#{label} #{pair}"
           else
             "#{label} #{backlog_sp_number(commit)}"
           end
    classes = ['backlog-sp-chip', "backlog-sp-chip--#{role}"]
    tone = backlog_velocity_tone(commit, velocity)
    classes << "is-#{tone}" if tone
    title = if velocity
              "#{label}: " + l(:title_backlog_commit_vs_velocity,
                               commit: backlog_sp_number(commit),
                               velocity: backlog_sp_number(velocity))
            else
              "#{label} #{backlog_sp_number(commit)}"
            end
    if compact && role.to_s == 'total'
      return content_tag(:span, { class: classes.join(' '), title: title }) do
        content_tag(:span, 'SP', class: 'backlog-sp-chip__unit') +
          content_tag(:span, pair, class: 'backlog-sp-chip__nums')
      end
    end
    content_tag(:span, text, class: classes.join(' '), title: title)
  end

  def backlog_velocity_tone(commit, velocity)
    return nil if velocity.nil? || velocity.to_f <= 0

    c = commit.to_f
    v = velocity.to_f
    return 'ok' if c <= v
    return 'warn' if c <= v * 1.2

    'over'
  end

  def backlog_velocity_metric_title(metric)
    velocity = defined?(@velocity) ? @velocity : nil
    return l(:label_backlog_velocity_empty) if velocity.blank? || velocity.sprints.blank?

    velocity.sprints.map do |row|
      "#{row.version.name}: #{backlog_sp_number(row.public_send(metric))}"
    end.join(' → ')
  end

  # Commit SP fields of the create / edit sprint modal. On a new sprint each field defaults to the matching
  # velocity (whole team for Commit SP, else that team): average Actual SP of the last N closed sprints
  # (N = Velocity window setting).
  def backlog_sprint_commit_sp_fields
    cfg = @settings || {}
    velocity = @velocity
    [
      {
        param: :commit_sp,
        input_id: 'backlog-create-sprint-commit-sp',
        issue_key: 'story_point_cfid',
        version_key: 'sp_commit_version_cfid',
        label: "#{l(:label_sprint_report_commit)} SP",
        default: velocity&.sp
      },
      {
        param: :commit_sp_be,
        input_id: 'backlog-create-sprint-commit-sp-be',
        issue_key: 'sp_be_cfid',
        version_key: 'sp_be_commit_version_cfid',
        label: l(:label_backlog_commit_be_sp),
        default: velocity&.be
      },
      {
        param: :commit_sp_fe,
        input_id: 'backlog-create-sprint-commit-sp-fe',
        issue_key: 'sp_fe_cfid',
        version_key: 'sp_fe_commit_version_cfid',
        label: l(:label_backlog_commit_fe_sp),
        default: velocity&.fe
      },
      {
        param: :commit_sp_qa,
        input_id: 'backlog-create-sprint-commit-sp-qa',
        issue_key: 'sp_qa_cfid',
        version_key: 'sp_qa_commit_version_cfid',
        label: l(:label_backlog_commit_qa_sp),
        default: velocity&.qa
      }
    ].select do |row|
      cfg[row[:issue_key]].to_i.positive? || cfg[row[:version_key]].to_i.positive?
    end
  end

  def backlog_version_cf_value(version, setting_key)
    cf = (@settings || {})[setting_key].to_i
    return '' unless version && cf.positive?

    version.custom_field_value(cf).to_s
  end

  def backlog_quota_chip(lane, stats)
    return '' if stats.blank?

    label = lane == 'sale' ? l(:label_intake_source_sale) : l(:label_intake_source_cs)
    if stats[:quota].nil?
      content_tag(:span, "#{label} #{backlog_sp_number(stats[:used])}",
                  class: "backlog-quota-chip backlog-quota-chip--#{lane} is-unlimited",
                  title: l(:label_intake_quota_unlimited))
    else
      content_tag(:span,
                  "#{label} #{backlog_sp_number(stats[:used])}/#{backlog_sp_number(stats[:quota])}",
                  class: "backlog-quota-chip backlog-quota-chip--#{lane}",
                  title: "#{backlog_sp_number(stats[:remaining])} #{l(:label_intake_quota_left)}")
    end
  end

  def backlog_goal_text(version)
    return '' unless version

    version.description.to_s.strip
  end

  def backlog_section_completion_counts(section)
    issues = Array(section&.issues)
    completed = issues.count { |i| i.status&.is_closed? }
    {
      completed: completed,
      open: issues.size - completed
    }
  end

  def backlog_cf_matches_version?(issue, cfid, version)
    return false if cfid.to_i <= 0 || version.nil?

    values = Array(issue.custom_field_value(cfid.to_i)).map { |v| v.to_s.strip }
    values.include?(version.id.to_s) || values.include?(version.name.to_s)
  end

  def backlog_cf_sp(issue, cfid)
    return 0 if cfid.to_i <= 0

    cv = issue.custom_value_for(cfid.to_i)
    backlog_sp_number(cv&.value.to_s.strip.empty? ? 0 : cv.value)
  end

  def backlog_complete_dod_candidates(section)
    version = section&.version
    return [] unless version

    cfg = @settings || SananAgile::ProjectSettings.load(@project.id)
    dod_id = cfg['dod_cfid'].to_i
    return [] if dod_id <= 0

    status_ids = Array(cfg['dod_checkbox_statuses']).map(&:to_i).reject(&:zero?)
    return [] if status_ids.empty?

    issues = Array(section.issues).select { |i| status_ids.include?(i.status_id) }
    tracker_ids = Array(cfg['dod_checkbox_trackers']).map(&:to_i).reject(&:zero?)
    issues = issues.select { |i| tracker_ids.include?(i.tracker_id) } if tracker_ids.any?
    issues.map do |issue|
      {
        id: issue.id,
        tracker: issue.tracker&.name.to_s,
        subject: issue.subject.to_s,
        sp: backlog_issue_sp(issue, cfg).to_f,
        sp_be: backlog_cf_sp(issue, cfg['sp_be_cfid']).to_f,
        sp_fe: backlog_cf_sp(issue, cfg['sp_fe_cfid']).to_f,
        sp_qa: backlog_cf_sp(issue, cfg['sp_qa_cfid']).to_f,
        closed: issue.status&.is_closed? ? true : false,
        dod: backlog_cf_matches_version?(issue, dod_id, version),
        be: backlog_cf_matches_version?(issue, cfg['done_be_cfid'], version),
        fe: backlog_cf_matches_version?(issue, cfg['done_fe_cfid'], version),
        qa: backlog_cf_matches_version?(issue, cfg['done_qa_cfid'], version)
      }
    end
  end

  def backlog_complete_move_options(current_version, open_versions)
    opts = [[l(:label_backlog_move_to_backlog), 'backlog']]
    Array(open_versions).each do |v|
      next if current_version && v.id == current_version.id

      opts << [v.name, v.id.to_s]
    end
    opts << [l(:label_backlog_keep_unfinished), '']
    opts
  end

  def backlog_agile_metrics_available?(project = @project)
    return false unless project
    return false unless Redmine::Plugin.installed?(:redmine_agile_metrics)
    User.current.allowed_to?(:view_agile_metrics, project)
  rescue StandardError
    false
  end

  def backlog_agile_metrics_path_for(project, version = nil)
    opts = {}
    opts[:version_id] = version.id if version
    project_agile_metrics_path(project, opts)
  end
end
