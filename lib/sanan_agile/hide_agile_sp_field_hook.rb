# frozen_string_literal: true
module SananAgile
  class HideAgileSpFieldHook < Redmine::Hook::ViewListener
    # Render 1 partial vào <head> trên mọi trang, nhưng partial sẽ tự kiểm tra project
    render_on :view_layouts_base_html_head, partial: 'sanan_agile/hide_sp_head'
  end
end
