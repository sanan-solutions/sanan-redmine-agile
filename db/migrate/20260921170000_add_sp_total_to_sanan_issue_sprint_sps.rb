# frozen_string_literal: true

class AddSpTotalToSananIssueSprintSps < ActiveRecord::Migration[6.1]
  def up
    add_column :sanan_issue_sprint_sps, :sp_total, :decimal, precision: 10, scale: 2

    # Legacy rows stored total as Σ team. New rows leave sp_total nil when unset.
    execute <<~SQL.squish
      UPDATE sanan_issue_sprint_sps
      SET sp_total = COALESCE(sp_be, 0) + COALESCE(sp_fe, 0) + COALESCE(sp_qa, 0)
      WHERE sp_total IS NULL
    SQL
  end

  def down
    remove_column :sanan_issue_sprint_sps, :sp_total
  end
end
