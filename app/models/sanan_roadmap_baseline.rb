# frozen_string_literal: true

class SananRoadmapBaseline < ActiveRecord::Base
  self.table_name = 'sanan_roadmap_baselines'

  belongs_to :project
  belongs_to :captured_by, class_name: 'User', optional: true

  validates :project_id, :year, :quarter, :captured_at, presence: true
  validates :quarter, inclusion: { in: 1..4 }
  validates :quarter, uniqueness: { scope: [:project_id, :year] }

  # [{ 'id', 'subject', 'sp_total', 'sp_done', 'story_count', 'done_count' }]
  def epics
    JSON.parse(snapshot.presence || '[]')
  rescue JSON::ParserError
    []
  end

  def epics=(list)
    self.snapshot = Array(list).to_json
  end
end
