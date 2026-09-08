# frozen_string_literal: true

class SananAgileMailer < Mailer
  def intake_ready_sp_alert(project, lane, ready_sp, threshold, users)
    @project = project
    @lane = lane.to_s
    @ready_sp = ready_sp
    @threshold = threshold
    @lane_label = @lane == 'sale' ? l(:label_sale_backlog) : l(:label_cs_backlog)
    @url = if @lane == 'sale'
             url_for(controller: 'sale_backlogs', action: 'show', project_id: project)
           else
             url_for(controller: 'cs_backlogs', action: 'show', project_id: project)
           end
    @pull_url = url_for(controller: 'backlogs', action: 'show', project_id: project)

    mail(
      to: users.map(&:mail).compact,
      subject: "[#{project.name}] #{l(:mail_subject_intake_ready_sp_alert, lane: @lane_label, sp: ready_sp)}"
    )
  end
end
