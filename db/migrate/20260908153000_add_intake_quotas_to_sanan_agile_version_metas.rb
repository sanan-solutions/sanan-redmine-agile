# frozen_string_literal: true

class AddIntakeQuotasToSananAgileVersionMetas < ActiveRecord::Migration[6.1]
  def change
    add_column :sanan_agile_version_metas, :cs_quota_sp, :decimal, precision: 10, scale: 2
    add_column :sanan_agile_version_metas, :sale_quota_sp, :decimal, precision: 10, scale: 2
  end
end
