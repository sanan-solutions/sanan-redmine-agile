# frozen_string_literal: true

# Story points are picked on the Fibonacci scale, which includes 0.5: integer SP fields become decimal ones.
# Stored values ("3") stay valid decimals.
class StoryPointFieldsAllowHalfPoints < ActiveRecord::Migration[5.2]
  KEYS = %w[size_be_cfid size_fe_cfid size_qa_cfid story_point_cfid
            sp_be_cfid sp_fe_cfid sp_qa_cfid sp_sprint_total_cfid].freeze

  def up
    store = Setting.plugin_sanan_redmine_agile
    return unless store.is_a?(Hash)

    ids = store.values.select { |v| v.is_a?(Hash) }.flat_map { |c| KEYS.map { |k| c[k].to_i } }.select(&:positive?).uniq
    IssueCustomField.where(id: ids, field_format: 'int').update_all(field_format: 'float')
  end

  def down
    # Values may now hold 0.5: keep the decimal format.
  end
end
