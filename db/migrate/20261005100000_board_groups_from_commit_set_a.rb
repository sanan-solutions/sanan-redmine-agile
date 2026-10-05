# frozen_string_literal: true

# The commit "development" statuses (set A, `commit_dev_status_ids`) are retired: commit follows the
# "This sprint" SP, and the Agile board column groups have their own status settings. Projects that had a
# set A keep the same board split: their open statuses outside A become the UAT group (closed statuses go
# to Closed and the rest to Development automatically).
class BoardGroupsFromCommitSetA < ActiveRecord::Migration[5.2]
  KEY = :sanan_redmine_agile

  def up
    store = Setting.send(:"plugin_#{KEY}")
    return unless store.is_a?(Hash) && store.any?

    open_ids = IssueStatus.where(is_closed: false).pluck(:id)
    changed = false
    store.each do |project_id, cfg|
      next unless cfg.is_a?(Hash) && cfg.key?('commit_dev_status_ids')

      set_a = Array(cfg['commit_dev_status_ids']).map(&:to_i).reject(&:zero?)
      uat = Array(cfg['agile_board_group_uat_status_ids']).map(&:to_i).reject(&:zero?)
      if set_a.any? && uat.empty?
        picked = %w[agile_board_group_dev_status_ids agile_board_group_closed_status_ids]
                 .flat_map { |k| Array(cfg[k]).map(&:to_i) }
        cfg['agile_board_group_uat_status_ids'] = (open_ids - set_a - picked).map(&:to_s)
      end
      cfg.delete('commit_dev_status_ids')
      store[project_id] = cfg
      changed = true
    end
    Setting.send(:"plugin_#{KEY}=", store) if changed
  end

  def down
    # Irreversible data clean-up (set A no longer exists); nothing to restore.
  end
end
