# frozen_string_literal: true

class SananRoadmapMove < ActiveRecord::Base
  self.table_name = 'sanan_roadmap_moves'

  # Moves of the same Epic by the same user closer than this are merged (see RoadmapsController#record_move!).
  MERGE_WINDOW = 10.minutes

  belongs_to :issue
  belongs_to :user, optional: true

  def self.label(year, quarter)
    year && quarter ? "Q#{quarter}/#{year}" : nil
  end

  def from_label
    self.class.label(from_year, from_quarter)
  end

  def to_label
    self.class.label(to_year, to_quarter)
  end

  # Planned → later planned quarter.
  def slip?
    return false unless from_year && from_quarter && to_year && to_quarter

    (to_year * 4 + to_quarter) > (from_year * 4 + from_quarter)
  end
end
