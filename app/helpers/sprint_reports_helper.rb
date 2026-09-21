# frozen_string_literal: true

module SprintReportsHelper
  def sprint_report_number(n)
    f = n.to_f
    f == f.to_i ? f.to_i : f.round(2)
  end

  def sprint_report_member_name(row)
    row.user ? link_to_user(row.user) : content_tag(:em, l(:label_sprint_report_unassigned))
  end

  def sprint_report_dates(version)
    parts = []
    parts << "#{l(:field_effective_date)}: #{format_date(version.effective_date)}" if version.effective_date
    if version.respond_to?(:start_date) && version.start_date
      parts << "#{l(:field_start_date)}: #{format_date(version.start_date)}"
    end
    parts.join(' · ')
  end

  def sprint_report_pct(n)
    return '—' if n.nil?

    "#{sprint_report_number(n)}%"
  end

  def sprint_report_agile_metrics_available?(project = @project)
    return false unless project
    return false unless Redmine::Plugin.installed?(:redmine_agile_metrics)
    User.current.allowed_to?(:view_agile_metrics, project)
  rescue StandardError
    false
  end

  def sprint_report_agile_metrics_path_for(project, version = nil)
    opts = {}
    opts[:version_id] = version.id if version
    project_agile_metrics_path(project, opts)
  end

  def sprint_report_chart_payload(history_rows, report)
    labels = history_rows.map { |r| r.version.name }
    completion_values = history_rows.map { |r| r.completion_pct }
    members = Array(report.members)
    {
      labels: {
        commit: l(:label_sprint_report_commit),
        actual: l(:label_sprint_report_actual),
        sp: l(:label_sprint_report_sp),
        be: l(:label_sprint_report_sp_be),
        fe: l(:label_sprint_report_sp_fe),
        qa: l(:label_sprint_report_sp_qa),
        completion: l(:label_sprint_report_completion_pct)
      },
      commitActual: {
        labels: labels,
        commit: history_rows.map { |r| r.commit_sp.to_f },
        actual: history_rows.map { |r| r.actual_sp.to_f }
      },
      roles: {
        labels: labels,
        be: history_rows.map { |r| r.actual_be.to_f },
        fe: history_rows.map { |r| r.actual_fe.to_f },
        qa: history_rows.map { |r| r.actual_qa.to_f }
      },
      completion: {
        labels: labels,
        values: completion_values,
        max: completion_values.compact.max || 100
      },
      members: {
        labels: members.map { |m| m.user ? m.user.name : l(:label_sprint_report_unassigned) },
        values: members.map { |m| m.sp.to_f }
      }
    }
  end

  def sprint_report_intake_label(source)
    case source.to_s
    when 'cs' then l(:label_intake_source_cs)
    when 'sale' then l(:label_intake_source_sale)
    else l(:label_intake_source_product)
    end
  end

  def sprint_report_source_badge(source)
    src = source.to_s
    src = 'product' unless %w[cs sale product].include?(src)
    content_tag(:span, sprint_report_intake_label(src),
                class: "sprint-intake-badge sprint-intake-badge--#{src}")
  end

  def sprint_report_intake_badge(issue, cfg = nil)
    cfg ||= @settings || SananAgile::ProjectSettings.load(@project.id)
    src = SananAgile::IntakeSource.value_for(issue, cfg) || 'product'
    sprint_report_source_badge(src)
  end

  def sprint_report_code_cell(done, sp)
    if done
      content_tag(:span, class: 'sr-code-flag sr-code-flag--done') do
        "#{l(:label_sprint_report_code_done)} · #{sprint_report_number(sp)} SP"
      end
    else
      content_tag(:span, '—', class: 'sr-code-flag sr-code-flag--skip')
    end
  end

  def sprint_report_yes_no_cell(yes)
    if yes
      content_tag(:span, l(:general_text_Yes), class: 'sr-code-flag sr-code-flag--done')
    else
      content_tag(:span, l(:general_text_No), class: 'sr-code-flag sr-code-flag--skip')
    end
  end

  def sprint_report_dod_cell(dod)
    if dod
      content_tag(:span, l(:label_sprint_report_dod_yes), class: 'sr-code-flag sr-code-flag--done')
    else
      content_tag(:span, l(:label_sprint_report_dod_no), class: 'sr-code-flag sr-code-flag--skip')
    end
  end

  def sprint_report_outcome_cell(outcome)
    key = outcome.to_s
    key = 'other' unless %w[done closed_without_dod carried_over unplanned in_sprint other].include?(key)
    content_tag(:span, l("label_sprint_report_outcome_#{key}"),
                class: "sr-outcome sr-outcome--#{key}")
  end

  def sprint_report_goal_met_badge(goal_met)
    key = goal_met.to_s
    key = 'unreviewed' unless %w[met partial missed unreviewed].include?(key)
    content_tag(:span, l("label_sprint_report_goal_met_#{key}"),
                class: "sr-badge sr-badge--goal-#{key}")
  end
end
