# frozen_string_literal: true

# Link a quarter move to the issue journal it wrote, so quick consecutive moves can be merged / undone.
class AddJournalIdToSananRoadmapMoves < ActiveRecord::Migration[6.1]
  def change
    add_column :sanan_roadmap_moves, :journal_id, :integer
  end
end
