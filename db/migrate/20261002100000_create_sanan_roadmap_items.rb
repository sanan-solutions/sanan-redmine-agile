# frozen_string_literal: true

# Product roadmap: places an Epic into a (year, quarter) column, independent of issue dates.
class CreateSananRoadmapItems < ActiveRecord::Migration[6.1]
  def change
    create_table :sanan_roadmap_items do |t|
      t.integer :project_id, null: false
      t.integer :issue_id, null: false
      t.integer :year, null: false
      t.integer :quarter, null: false
      t.integer :position, null: false, default: 0
      t.string :health, limit: 20
      t.timestamps null: false
    end
    add_index :sanan_roadmap_items, :issue_id, unique: true, name: 'idx_sanan_roadmap_items_issue'
    add_index :sanan_roadmap_items, [:project_id, :year], name: 'idx_sanan_roadmap_items_project_year'
  end
end
