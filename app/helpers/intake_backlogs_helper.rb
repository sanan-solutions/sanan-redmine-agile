# frozen_string_literal: true

module IntakeBacklogsHelper
  def intake_issue_sp(issue)
    f = SananAgile::IntakeBacklogQuery.new(@project, lane: @lane, cfg: @settings).story_point_for(issue)
    f == f.to_i ? f.to_i : f.round(2)
  end

  def intake_lane_title
    @lane == 'sale' ? l(:label_sale_backlog) : l(:label_cs_backlog)
  end
end
