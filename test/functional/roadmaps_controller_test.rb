# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class RoadmapsControllerTest < Redmine::ControllerTest
  include SananRoadmapTestHelper
  fixtures(*ROADMAP_FIXTURES)

  def setup
    @project = enable_roadmap!
    User.current = nil
    @request.session[:user_id] = 2 # jsmith, Manager on project 1
    @epic = create_epic!
  end

  def test_show
    get :show, params: { project_id: @project.identifier, year: 2026 }
    assert_response :success
    assert_select '#sanan-roadmap'
    assert_select 'script#roadmap-data'
  end

  def test_show_404_when_roadmap_tab_disabled
    enable_roadmap!(@project, 'roadmap_enabled' => '0')
    get :show, params: { project_id: @project.identifier }
    assert_response :not_found
  end

  def test_data_returns_products_json
    plan!(@epic, 2026, 3)
    get :data, params: { project_id: @project.identifier, year: 2026 }
    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    product = json['products'].first
    assert_equal @project.id, product['id']
    assert(product['quarters']['3'].any? { |e| e['id'] == @epic.id })
    assert_not product.key?('all_epics')
  end

  def test_move_plans_epic_records_history_and_silent_journal
    assert_difference -> { Journal.count } => 1, -> { SananRoadmapMove.count } => 1 do
      patch :move, params: { project_id: @project.identifier, issue_id: @epic.id, year: 2026, quarter: 2 }
    end
    assert_response :success
    item = SananRoadmapItem.find_by(issue_id: @epic.id)
    assert_equal [2026, 2, 'on_track'], [item.year, item.quarter, item.health]
    move = SananRoadmapMove.last
    assert_equal [nil, 'Q2/2026'], [move.from_label, move.to_label]
    assert_match 'Q2/2026', Journal.last.notes
  end

  def move!(quarter, year = 2026)
    patch :move, params: { project_id: @project.identifier, issue_id: @epic.id, year: year, quarter: quarter }
    assert_response :success
  end

  def test_quick_move_and_undo_leaves_no_history
    assert_no_difference -> { Journal.count } do
      assert_no_difference -> { SananRoadmapMove.count } do
        move!(2)
        move!(0)
      end
    end
    assert_nil SananRoadmapItem.find_by(issue_id: @epic.id)
  end

  def test_quick_consecutive_moves_are_merged
    plan!(@epic, 2026, 1)
    assert_difference -> { SananRoadmapMove.count } => 1, -> { Journal.count } => 1 do
      move!(2)
      move!(3)
    end
    move = SananRoadmapMove.last
    assert_equal ['Q1/2026', 'Q3/2026'], [move.from_label, move.to_label]
    assert_equal move.journal_id, Journal.last.id
    assert_match 'Q1/2026 → Q3/2026', Journal.last.notes
  end

  def test_moves_outside_the_merge_window_are_kept_apart
    plan!(@epic, 2026, 1)
    move!(2)
    SananRoadmapMove.last.update_column(:created_at, 11.minutes.ago)
    assert_difference -> { SananRoadmapMove.count } => 1 do
      move!(3)
    end
  end

  def test_moves_by_another_user_are_not_merged
    plan!(@epic, 2026, 1)
    move!(2)
    SananRoadmapMove.last.update_column(:user_id, 3)
    assert_difference -> { SananRoadmapMove.count } => 1 do
      move!(1)
    end
  end

  def test_reorder_within_quarter_does_not_record_history
    plan!(@epic, 2026, 2)
    assert_no_difference -> { SananRoadmapMove.count } do
      patch :move, params: { project_id: @project.identifier, issue_id: @epic.id, year: 2026, quarter: 2,
                             ordered_ids: [@epic.id] }
    end
    assert_response :success
  end

  def test_move_to_unplanned_removes_item
    plan!(@epic, 2026, 2)
    patch :move, params: { project_id: @project.identifier, issue_id: @epic.id, quarter: 0 }
    assert_response :success
    assert_nil SananRoadmapItem.find_by(issue_id: @epic.id)
    assert_equal 'Q2/2026', SananRoadmapMove.last.from_label
    assert_nil SananRoadmapMove.last.to_label
  end

  def test_move_still_works_from_portfolio_when_roadmap_tab_disabled
    enable_roadmap!(@project, 'roadmap_enabled' => '0')
    patch :move, params: { project_id: @project.identifier, issue_id: @epic.id, year: 2026, quarter: 1 }
    assert_response :success
  end

  def test_move_rejects_invalid_quarter
    patch :move, params: { project_id: @project.identifier, issue_id: @epic.id, year: 2026, quarter: 7 }
    assert_response :unprocessable_entity
  end

  def test_move_rejects_non_epic_issue
    patch :move, params: { project_id: @project.identifier, issue_id: 1, year: 2026, quarter: 1 }
    assert_response :not_found
  end

  def test_move_requires_manage_permission
    Role.find(1).remove_permission!(:manage_roadmap)
    patch :move, params: { project_id: @project.identifier, issue_id: @epic.id, year: 2026, quarter: 1 }
    assert_response :forbidden
  end

  def test_update_span_and_move_keeps_span
    plan!(@epic, 2026, 2)
    patch :update_span, params: { project_id: @project.identifier, issue_id: @epic.id, span: 2 }
    assert_response :success
    item = SananRoadmapItem.find_by(issue_id: @epic.id)
    assert_equal [2026, 3], [item.end_year, item.end_quarter]

    patch :move, params: { project_id: @project.identifier, issue_id: @epic.id, year: 2026, quarter: 4 }
    assert_response :success
    item.reload
    assert_equal [2026, 4, 2027, 1], [item.year, item.quarter, item.end_year, item.end_quarter]
  end

  def test_update_span_requires_planned_epic
    patch :update_span, params: { project_id: @project.identifier, issue_id: @epic.id, span: 2 }
    assert_response :unprocessable_entity
  end

  def test_update_health
    plan!(@epic, 2026, 1)
    patch :update_health, params: { project_id: @project.identifier, issue_id: @epic.id, health: 'off_track' }
    assert_response :success
    assert_equal 'off_track', SananRoadmapItem.find_by(issue_id: @epic.id).health

    patch :update_health, params: { project_id: @project.identifier, issue_id: @epic.id, health: 'bogus' }
    assert_response :unprocessable_entity
  end

  def test_create_and_destroy_baseline
    plan!(@epic, 2026, 4)
    post :create_baseline, params: { project_id: @project.identifier, year: 2026, quarter: 4 }
    assert_response :success
    baseline = SananRoadmapBaseline.find_by(project_id: @project.id, year: 2026, quarter: 4)
    assert_equal [@epic.id], baseline.epics.map { |e| e['id'] }
    assert_equal 2, baseline.captured_by_id

    delete :destroy_baseline, params: { project_id: @project.identifier, year: 2026, quarter: 4 }
    assert_response :success
    assert_nil SananRoadmapBaseline.find_by(id: baseline.id)
  end

  def test_baseline_requires_manage_permission
    Role.find(1).remove_permission!(:manage_roadmap)
    post :create_baseline, params: { project_id: @project.identifier, year: 2026, quarter: 4 }
    assert_response :forbidden
  end
end
