# frozen_string_literal: true

class AddSprintGoalAndCommitIdsToVersionMetas < ActiveRecord::Migration[6.1]
  def change
    add_column :sanan_agile_version_metas, :goal_met, :string, limit: 16, default: 'unreviewed'
    add_column :sanan_agile_version_metas, :goal_note, :text
    add_column :sanan_agile_version_metas, :commit_issue_ids, :text
  end
end
