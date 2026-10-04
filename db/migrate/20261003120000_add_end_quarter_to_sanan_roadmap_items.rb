# frozen_string_literal: true

# Multi-quarter Epics: optional last quarter of the span (nil = single quarter).
class AddEndQuarterToSananRoadmapItems < ActiveRecord::Migration[6.1]
  def change
    add_column :sanan_roadmap_items, :end_year, :integer
    add_column :sanan_roadmap_items, :end_quarter, :integer
  end
end
