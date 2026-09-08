# frozen_string_literal: true

class SananAgileVersionMeta < ActiveRecord::Base
  self.table_name = 'sanan_agile_version_metas'

  belongs_to :version
  validates :version_id, presence: true, uniqueness: true
end
