# frozen_string_literal: true

class CreateSananIssueSpTables < ActiveRecord::Migration[6.1]
  def up
    create_table :sanan_issue_sp_sizes do |t|
      t.integer :issue_id, null: false
      t.decimal :sp_be, precision: 10, scale: 2
      t.decimal :sp_fe, precision: 10, scale: 2
      t.decimal :sp_qa, precision: 10, scale: 2
      t.timestamps null: false
    end
    add_index :sanan_issue_sp_sizes, :issue_id, unique: true, name: 'idx_sanan_issue_sp_sizes_issue'

    create_table :sanan_issue_sprint_sps do |t|
      t.integer :issue_id, null: false
      t.integer :version_id, null: false
      t.decimal :sp_be, precision: 10, scale: 2
      t.decimal :sp_fe, precision: 10, scale: 2
      t.decimal :sp_qa, precision: 10, scale: 2
      t.datetime :captured_at, null: false
      t.integer :captured_by_id
      t.timestamps null: false
    end
    add_index :sanan_issue_sprint_sps, [:issue_id, :version_id],
              unique: true, name: 'idx_sanan_issue_sprint_sps_issue_version'
    add_index :sanan_issue_sprint_sps, :version_id, name: 'idx_sanan_issue_sprint_sps_version'

    copy_team_cf_into_size
  end

  def down
    drop_table :sanan_issue_sprint_sps
    drop_table :sanan_issue_sp_sizes
  end

  private

  def copy_team_cf_into_size
    store = Setting.plugin_sanan_redmine_agile
    return unless store.is_a?(Hash)

    now = Time.now.utc
    store.each do |_pid, cfg|
      next unless cfg.is_a?(Hash)

      be = cfg['sp_be_cfid'].to_i
      fe = cfg['sp_fe_cfid'].to_i
      qa = cfg['sp_qa_cfid'].to_i
      next if be <= 0 && fe <= 0 && qa <= 0

      ids_by_issue = Hash.new { |h, k| h[k] = {} }
      [[be, 'sp_be'], [fe, 'sp_fe'], [qa, 'sp_qa']].each do |cfid, col|
        next if cfid <= 0

        CustomValue.where(customized_type: 'Issue', custom_field_id: cfid)
                   .pluck(:customized_id, :value)
                   .each do |iid, val|
          num = parse_num(val)
          ids_by_issue[iid.to_i][col] = num unless num.nil?
        end
      end

      existing = SananIssueSpSize.where(issue_id: ids_by_issue.keys).pluck(:issue_id).to_set
      rows = ids_by_issue.filter_map do |issue_id, cols|
        next if existing.include?(issue_id) || cols.empty?

        {
          issue_id: issue_id,
          sp_be: cols['sp_be'],
          sp_fe: cols['sp_fe'],
          sp_qa: cols['sp_qa'],
          created_at: now,
          updated_at: now
        }
      end
      SananIssueSpSize.insert_all(rows) if rows.any?
    end
  rescue StandardError => e
    say "sanan_issue_sp_sizes copy skipped: #{e.message}"
  end

  def parse_num(val)
    s = val.to_s.strip.tr(',', '.')
    return nil if s.empty?

    Float(s)
  rescue ArgumentError, TypeError
    nil
  end
end
