# frozen_string_literal: true

class SananRoadmapItem < ActiveRecord::Base
  self.table_name = 'sanan_roadmap_items'

  HEALTH_VALUES = %w[on_track at_risk off_track].freeze
  MAX_SPAN = 4 # quarters

  belongs_to :project
  belongs_to :issue

  validates :project_id, :issue_id, :year, :quarter, presence: true
  validates :issue_id, uniqueness: true
  validates :quarter, inclusion: { in: 1..4 }
  validates :year, numericality: { only_integer: true, greater_than: 1999, less_than: 2200 }
  validates :health, inclusion: { in: HEALTH_VALUES }, allow_blank: true
  validate :validate_span

  # Quarters are compared as year * 4 + (quarter - 1).
  def self.key(year, quarter)
    year.to_i * 4 + (quarter.to_i - 1)
  end

  def self.from_key(key)
    [key / 4, key % 4 + 1]
  end

  def health_key
    HEALTH_VALUES.include?(health.to_s) ? health.to_s : 'on_track'
  end

  def start_key
    self.class.key(year, quarter)
  end

  def end_key
    end_year && end_quarter ? self.class.key(end_year, end_quarter) : start_key
  end

  # Number of quarters covered (1 = single quarter).
  def span
    end_key - start_key + 1
  end

  # Sets the span length in quarters, keeping the start (1 clears the end).
  def span=(quarters)
    n = quarters.to_i.clamp(1, MAX_SPAN)
    if n == 1
      self.end_year = self.end_quarter = nil
    else
      self.end_year, self.end_quarter = self.class.from_key(start_key + n - 1)
    end
  end

  def covers?(year, quarter)
    (start_key..end_key).cover?(self.class.key(year, quarter))
  end

  private

  def validate_span
    return if end_year.nil? && end_quarter.nil?
    return errors.add(:end_quarter, :invalid) unless end_year && (1..4).cover?(end_quarter.to_i)

    errors.add(:end_quarter, :invalid) unless end_key >= start_key && span <= MAX_SPAN
  end
end
