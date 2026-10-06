# frozen_string_literal: true

# Plugin-wide (global) settings: a project now stores only what differs from them. Project settings saved
# before kept every key, so values still equal to the built-in defaults are dropped: those projects then
# follow the global settings (which start equal to the defaults, so nothing changes until an admin edits them).
class CompactProjectSettingsForGlobalDefaults < ActiveRecord::Migration[5.2]
  def up
    store = Setting.plugin_sanan_redmine_agile
    return unless store.is_a?(Hash)

    defaults = SananAgile::ProjectSettings::DEFAULTS
    keep = SananAgile::ProjectSettings::PROJECT_ONLY_KEYS
    data = store.each_with_object({}) do |(key, cfg), out|
      out[key] = if key == SananAgile::ProjectSettings::GLOBAL_KEY || !cfg.is_a?(Hash)
                   cfg
                 else
                   cfg.reject do |k, v|
                     defaults.key?(k) && !keep.include?(k) &&
                       SananAgile::ProjectSettings.comparable(v) == SananAgile::ProjectSettings.comparable(defaults[k])
                   end
                 end
    end
    Setting.plugin_sanan_redmine_agile = JSON.parse(data.to_json)
  end

  def down
    # Nothing to restore: the dropped values are the defaults, which projects still get.
  end
end
