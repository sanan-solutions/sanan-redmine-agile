# frozen_string_literal: true

class SaleBacklogsController < IntakeBacklogsController
  private

  def lane
    'sale'
  end

  def view_permission
    :view_sale_backlog
  end

  def manage_permission
    :manage_sale_backlog
  end

  def enabled_setting_key
    'sale_backlog_enabled'
  end
end
