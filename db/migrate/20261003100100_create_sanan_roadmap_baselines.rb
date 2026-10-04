# frozen_string_literal: true

# Quarter plan locked at a point in time (snapshot of the Epics planned in that quarter).
class CreateSananRoadmapBaselines < ActiveRecord::Migration[6.1]
  def change
    create_table :sanan_roadmap_baselines do |t|
      t.integer :project_id, null: false
      t.integer :year, null: false
      t.integer :quarter, null: false
      t.text :snapshot
      t.integer :captured_by_id
      t.datetime :captured_at, null: false
      t.timestamps null: false
    end
    add_index :sanan_roadmap_baselines, [:project_id, :year, :quarter], unique: true,
              name: 'idx_sanan_roadmap_baselines_project_quarter'
  end
end
