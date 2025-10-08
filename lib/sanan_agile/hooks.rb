# lib/sanan_agile/hooks.rb
module SananAgile
  class Hooks < Redmine::Hook::ViewListener
    render_on :view_agile_board_bottom, partial: 'sanan_agile/issue_card_boot'
  end
end
