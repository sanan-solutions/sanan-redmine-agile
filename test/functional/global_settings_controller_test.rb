# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class GlobalSettingsControllerTest < Redmine::ControllerTest
  include SananRoadmapTestHelper
  tests SananAgile::GlobalSettingsController
  fixtures(*ROADMAP_FIXTURES)

  def test_admin_edits_the_global_settings
    @request.session[:user_id] = 1
    get :edit
    assert_response :success
    assert_select 'form[action=?]', '/admin/sanan_agile'
    assert_select 'input[name="settings[sanan_agile_enabled]"]', 0 # project only
    assert_select 'select[name="settings[backlog_version_id]"]', 0

    put :update, params: { settings: { sp_total_formula: 'avg' } }
    assert_redirected_to '/admin/sanan_agile'
    assert_equal 'avg', SananAgile::ProjectSettings.load_global['sp_total_formula']
  end

  def test_non_admin_is_refused
    @request.session[:user_id] = 2
    get :edit
    assert_response :forbidden
  end
end
