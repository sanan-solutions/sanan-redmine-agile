# lib/sanan_agile/issue_card_hook.rb
module SananAgile
  class IssueCardHook < Redmine::Hook::ViewListener
    render_on :view_agile_board_bottom, partial: 'sanan_agile/issue_card_boot'
  end
end
