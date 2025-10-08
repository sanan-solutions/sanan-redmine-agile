# frozen_string_literal: true
module SananAgile
  class AgileData < ActiveRecord::Base
    self.table_name = 'agile_data'
    belongs_to :issue
  end
end
