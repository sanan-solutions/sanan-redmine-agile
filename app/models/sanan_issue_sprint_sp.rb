# frozen_string_literal: true

class SananIssueSprintSp < ActiveRecord::Base
  self.table_name = 'sanan_issue_sprint_sps'

  belongs_to :issue
  belongs_to :version
  belongs_to :captured_by, class_name: 'User', optional: true

  validates :issue_id, :version_id, presence: true
  validates :issue_id, uniqueness: { scope: :version_id }

  def team_total
    [sp_be, sp_fe, sp_qa].compact.map(&:to_f).sum
  end

  def display_total
    sp_total.nil? ? team_total : sp_total
  end
end
