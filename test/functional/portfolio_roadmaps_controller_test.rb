# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class PortfolioRoadmapsControllerTest < Redmine::ControllerTest
  include SananRoadmapTestHelper
  fixtures(*ROADMAP_FIXTURES)

  def setup
    enable_roadmap!(Project.find(1))
    # Module on, but the project Roadmap tab is off: still selectable on the portfolio.
    enable_roadmap!(Project.find(2), 'roadmap_enabled' => '0')
    Role.find(2).add_permission!(:view_roadmap) # jsmith is Developer on project 2
    User.current = nil
    @request.session[:user_id] = 2 # jsmith: Manager on project 1, Developer on project 2
  end

  def product_ids
    ActiveSupport::JSON.decode(response.body)['products'].map { |p| p['id'] }
  end

  def test_anonymous_is_redirected_to_login
    @request.session[:user_id] = nil
    get :show
    assert_response :redirect
  end

  def test_show_lists_all_available_products_by_default
    get :show
    assert_response :success
    assert_select '#rm-picker input[name="project_ids[]"]', 2
    get :data
    assert_equal [1, 2], product_ids.sort
  end

  def test_project_without_module_is_not_available
    Project.find(2).disable_module!(:sanan_agile)
    get :data
    assert_equal [1], product_ids
  end

  def test_project_without_view_permission_is_not_available
    Role.find(2).remove_permission!(:view_roadmap)
    get :data
    assert_equal [1], product_ids
  end

  def test_developer_can_view_but_not_plan
    get :data
    products = ActiveSupport::JSON.decode(response.body)['products'].index_by { |p| p['id'] }
    assert products[1]['can_manage']
    assert_not products[2]['can_manage']
    assert_equal [], products[2]['unplanned']
  end

  def test_selection_is_saved_per_user
    get :show, params: { apply: 1, project_ids: ['2'] }
    assert_response :success
    assert_equal [2], User.find(2).pref[:sanan_roadmap_project_ids]

    get :data
    assert_equal [2], product_ids
  end

  def test_selection_ignores_unavailable_projects
    get :show, params: { apply: 1, project_ids: %w[1 999] }
    assert_equal [1], User.find(2).pref[:sanan_roadmap_project_ids]
  end

  def test_empty_selection_shows_no_rows
    get :show, params: { apply: 1 }
    assert_response :success
    get :data
    assert_equal [], product_ids
  end

  def test_product_without_roadmap_tab_has_no_roadmap_link
    get :data
    products = ActiveSupport::JSON.decode(response.body)['products'].index_by { |p| p['id'] }
    assert products[1]['urls']['roadmap']
    assert_nil products[2]['urls']['roadmap']
  end
end
