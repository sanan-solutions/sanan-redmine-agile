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
end
