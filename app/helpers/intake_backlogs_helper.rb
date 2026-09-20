# frozen_string_literal: true

module IntakeBacklogsHelper
  def intake_issue_sp(issue)
    f = SananAgile::IntakeBacklogQuery.new(@project, lane: @lane, cfg: @settings).story_point_for(issue)
    f == f.to_i ? f.to_i : f.round(2)
  end

  def intake_lane_title
    @lane == 'sale' ? l(:label_sale_backlog) : l(:label_cs_backlog)
  end

  def intake_ready_age_cell(issue, health, ready_ids)
    age = health.age_days(issue, ready_ids)
    return content_tag(:span, '—', class: 'intake-age') if age.nil?

    css = health.sla_breach?(issue, ready_ids) ? 'intake-age is-breach' : 'intake-age'
    title = l(:label_intake_age_days, count: age)
    content_tag(:span, title, class: css, title: title)
  end

  def intake_customer_deadline_enabled?
    @settings['customer_deadline_cfid'].to_i.positive?
  end

  def intake_customer_deadline_raw(issue)
    cfid = @settings['customer_deadline_cfid'].to_i
    return nil if cfid <= 0

    issue.custom_value_for(cfid)&.value.to_s.strip.presence
  end

  def intake_customer_deadline_date(issue)
    raw = intake_customer_deadline_raw(issue)
    return nil if raw.blank?

    Time.zone.parse(raw).to_date
  rescue ArgumentError, TypeError
    begin
      Date.parse(raw)
    rescue ArgumentError, TypeError
      nil
    end
  end

  def intake_customer_deadline_cell(issue)
    date = intake_customer_deadline_date(issue)
    return content_tag(:span, '—', class: 'intake-deadline') unless date

    overdue = !issue.closed? && date < Date.current
    css = overdue ? 'intake-deadline is-overdue' : 'intake-deadline'
    content_tag(:span, format_date(date), class: css, title: l(:label_customer_deadline))
  end

  # Expected release date from the ReleaseVersion the issue is attached to.
  def intake_release_on_cell(issue)
    return content_tag(:span, '—', class: 'intake-release-on') unless defined?(ReleaseVersion)

    release = ReleaseVersion.for_issue(issue)
    return content_tag(:span, '—', class: 'intake-release-on') unless release

    unless release.release_on
      return content_tag(:span, '—', class: 'intake-release-on', title: release.name)
    end

    link_to format_date(release.release_on),
            project_release_path(@project, release),
            class: 'intake-release-on',
            title: release.name
  rescue
    content_tag(:span, '—', class: 'intake-release-on')
  end
end
