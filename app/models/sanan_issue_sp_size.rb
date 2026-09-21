# frozen_string_literal: true

class SananIssueSpSize < ActiveRecord::Base
  self.table_name = 'sanan_issue_sp_sizes'

  belongs_to :issue
  validates :issue_id, presence: true, uniqueness: true
end
