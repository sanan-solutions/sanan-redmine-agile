# frozen_string_literal: true

class CreateSananAgileVersionMetas < ActiveRecord::Migration[6.1]
  def change
    create_table :sanan_agile_version_metas do |t|
      t.integer :version_id, null: false
      t.date :start_date
      t.timestamps null: false
    end
    add_index :sanan_agile_version_metas, :version_id,
              unique: true, name: 'idx_sanan_agile_version_metas_version'
  end
end
