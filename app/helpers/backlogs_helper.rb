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
