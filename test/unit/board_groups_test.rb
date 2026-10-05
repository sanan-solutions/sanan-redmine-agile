# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class BoardGroupsTest < ActiveSupport::TestCase
  include SananRoadmapTestHelper
  fixtures(*ROADMAP_FIXTURES)

  # Fixture statuses: 1 New, 2 Assigned, 3 Resolved, 4 Feedback, 5 Closed (closed), 6 Rejected (closed)
  def test_unpicked_statuses_go_to_development_or_closed
    groups = SananAgile::BoardGroups.status_groups({})
    assert_equal %w[dev dev dev dev], groups.values_at(1, 2, 3, 4)
    assert_equal %w[closed closed], groups.values_at(5, 6)
  end

  def test_settings_assign_statuses_to_groups
    cfg = {
      'agile_board_group_dev_status_ids' => ['', '3'],
      'agile_board_group_uat_status_ids' => ['6'],
      'agile_board_group_closed_status_ids' => ['4']
    }
    groups = SananAgile::BoardGroups.status_groups(cfg)
    assert_equal 'dev', groups[3]    # picked for Development
    assert_equal 'uat', groups[6]    # a closed status picked for UAT
    assert_equal 'closed', groups[4] # an open status picked for Closed
    assert_equal 'dev', groups[1]    # not picked anywhere, open: Development
    assert_equal 'closed', groups[5] # not picked anywhere: automatic (closed flag)
  end

  def test_closed_choice_wins_when_a_status_is_picked_twice
    cfg = { 'agile_board_group_dev_status_ids' => ['5'], 'agile_board_group_closed_status_ids' => ['5'] }
    assert_equal 'closed', SananAgile::BoardGroups.status_groups(cfg)[5]
  end

  def test_migration_turns_set_a_into_the_uat_group
    require File.expand_path('../../db/migrate/20261005100000_board_groups_from_commit_set_a', __dir__)
    store = Setting.plugin_sanan_redmine_agile || {}
    fresh = -> { JSON.parse(SananAgile::ProjectSettings::DEFAULTS.to_json) } # no shared objects (YAML aliases)
    store['1'] = fresh.call.merge('commit_dev_status_ids' => %w[1 2])
    store['2'] = fresh.call.merge('commit_dev_status_ids' => %w[1], 'agile_board_group_uat_status_ids' => %w[4])
    Setting.plugin_sanan_redmine_agile = store
    ActiveRecord::Migration.suppress_messages { BoardGroupsFromCommitSetA.new.up }

    after = Setting.plugin_sanan_redmine_agile
    assert_equal %w[3 4], after['1']['agile_board_group_uat_status_ids'].sort # open statuses outside set A
    assert_equal %w[4], after['2']['agile_board_group_uat_status_ids']        # already set: kept
    assert_not after['1'].key?('commit_dev_status_ids')
    groups = SananAgile::BoardGroups.status_groups(after['1'])
    assert_equal %w[dev dev uat uat closed closed], groups.values_at(1, 2, 3, 4, 5, 6)
  end
end
