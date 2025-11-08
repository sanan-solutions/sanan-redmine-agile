# plugins/sanan_redmine_agile/db/migrate/20251101_release_items_compact.rb
class ReleaseItemsCompact < ActiveRecord::Migration[5.2]
  def up
    # cột bổ sung
    add_column :release_items, :added_at,   :datetime, null: true
    add_column :release_items, :added_by_id, :integer, null: true


    # 2) backfill timestamp bằng hàm phù hợp từng DB
    adapter = ActiveRecord::Base.connection.adapter_name
    now_sql =
      case adapter
      when /SQLite/i      then "datetime('now')"         # UTC
      when /PostgreSQL/i  then "CURRENT_TIMESTAMP"
      else                      "CURRENT_TIMESTAMP"      # MySQL/MariaDB
      end
    execute "UPDATE release_items SET added_at = #{now_sql} WHERE added_at IS NULL"

    # 3) ràng buộc NOT NULL
    change_column_null :release_items, :added_at, false

    # index chống trùng cặp (phòng user add cùng issue nhiều lần vào cùng 1 release)
    add_index :release_items, [:release_version_id, :issue_id],
              unique: true, name: 'idx_rel_items_rel_issue_unique'

    # ép “mỗi issue chỉ thuộc đúng 1 release” (hiện tại)
    # NOTE: nếu tương lai muốn cho 1 issue thuộc nhiều release → chỉ cần drop index này
    add_index :release_items, :issue_id, unique: true, name: 'idx_rel_items_issue_unique'
  end

  def down
    remove_index :release_items, name: 'idx_rel_items_issue_unique' rescue nil
    remove_index :release_items, name: 'idx_rel_items_rel_issue_unique' rescue nil
    remove_column :release_items, :added_by_id rescue nil
    remove_column :release_items, :added_at    rescue nil
  end
end
