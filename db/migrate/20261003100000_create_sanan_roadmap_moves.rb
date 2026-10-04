# frozen_string_literal: true

# History of an Epic's quarter changes on the Product Roadmap (nil year/quarter = Unplanned).
class CreateSananRoadmapMoves < ActiveRecord::Migration[6.1]
  def change
    create_table :sanan_roadmap_moves do |t|
      t.integer :project_id, null: false
      t.integer :issue_id, null: false
      t.integer :from_year
      t.integer :from_quarter
      t.integer :to_year
      t.integer :to_quarter
      t.integer :user_id
      t.datetime :created_at, null: false
    end
    add_index :sanan_roadmap_moves, :issue_id, name: 'idx_sanan_roadmap_moves_issue'
  end
end
