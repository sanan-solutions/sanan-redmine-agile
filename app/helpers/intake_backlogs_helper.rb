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
end
