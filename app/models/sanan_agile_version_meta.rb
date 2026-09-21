# frozen_string_literal: true

class SananAgileVersionMeta < ActiveRecord::Base
  self.table_name = 'sanan_agile_version_metas'

  GOAL_MET_VALUES = %w[met partial missed unreviewed].freeze

  belongs_to :version
  validates :version_id, presence: true, uniqueness: true
  validates :goal_met, inclusion: { in: GOAL_MET_VALUES }, allow_blank: true

  def commit_issue_ids_list
    JSON.parse(commit_issue_ids.presence || '[]').map(&:to_i).reject(&:zero?).uniq
  rescue JSON::ParserError, TypeError
    []
  end

  def commit_issue_ids_list=(ids)
    self.commit_issue_ids = Array(ids).map(&:to_i).reject(&:zero?).uniq.to_json
  end

  def goal_met_key
    v = goal_met.to_s
    GOAL_MET_VALUES.include?(v) ? v : 'unreviewed'
  end
end
