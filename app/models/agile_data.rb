# frozen_string_literal: true
class AgileData < ActiveRecord::Base
  self.table_name = 'agile_data'
  belongs_to :issue
end
