# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class ProjectSettingsGlobalTest < ActiveSupport::TestCase
  include SananRoadmapTestHelper
  fixtures(*ROADMAP_FIXTURES)

  PS = SananAgile::ProjectSettings

  def setup
    Setting.plugin_sanan_redmine_agile = {}
  end

  def test_a_new_project_follows_the_global_settings
    PS.save_global('sp_total_formula' => 'max', 'velocity_window' => '5')
    cfg = PS.load(3)
    assert_equal 'max', cfg['sp_total_formula']
    assert_equal '5', cfg['velocity_window']
    assert_includes PS.inherited_keys(3), 'sp_total_formula'
  end

  def test_a_project_stores_only_what_differs_and_follows_later_global_changes
    PS.save_global('sp_total_formula' => 'max', 'velocity_window' => '5')
    PS.save(1, 'sanan_agile_enabled' => '1', 'sp_total_formula' => 'max', 'velocity_window' => '3',
               'standard_tracker' => ['', '1'])
    stored = Setting.plugin_sanan_redmine_agile['1']
    assert_equal '3', stored['velocity_window']    # differs from global: kept
    assert_not stored.key?('sp_total_formula')      # same as global: inherited
    assert_equal '1', stored['sanan_agile_enabled'] # project only: always kept

    PS.save_global('sp_total_formula' => 'avg', 'velocity_window' => '5')
    assert_equal 'avg', PS.load(1)['sp_total_formula']
    assert_equal '3', PS.load(1)['velocity_window']
  end

  def test_project_only_settings_are_never_global
    PS.save_global('backlog_version_id' => '9', 'sanan_agile_enabled' => '1')
    assert_not Setting.plugin_sanan_redmine_agile['_global'].key?('backlog_version_id')
    assert_equal '0', PS.load(3)['sanan_agile_enabled']
  end

  def test_compact_migration_drops_values_equal_to_the_defaults
    require File.expand_path('../../db/migrate/20261005110000_compact_project_settings_for_global_defaults', __dir__)
    full = JSON.parse(PS::DEFAULTS.merge('sanan_agile_enabled' => '1', 'velocity_window' => '5').to_json)
    Setting.plugin_sanan_redmine_agile = { '1' => full }
    ActiveRecord::Migration.suppress_messages { CompactProjectSettingsForGlobalDefaults.new.up }
    stored = Setting.plugin_sanan_redmine_agile['1']
    assert_equal({ 'sanan_agile_enabled' => '1', 'velocity_window' => '5' }.sort, stored.slice('sanan_agile_enabled', 'velocity_window').sort)
    assert_not stored.key?('sp_total_formula')
    assert_equal PS::DEFAULTS['sp_total_formula'], PS.load(1)['sp_total_formula']
  end
end
