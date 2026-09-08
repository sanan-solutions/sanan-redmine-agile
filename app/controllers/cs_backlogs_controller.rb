# frozen_string_literal: true

class CsBacklogsController < IntakeBacklogsController
  private

  def lane
    'cs'
  end

  def view_permission
    :view_cs_backlog
  end

  def manage_permission
    :manage_cs_backlog
  end

  def enabled_setting_key
    'cs_backlog_enabled'
  end
end
