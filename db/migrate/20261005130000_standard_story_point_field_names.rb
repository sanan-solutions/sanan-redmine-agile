# frozen_string_literal: true

# One naming pattern for the story point fields chosen in the settings: "<Group> - <Part>".
# A field is renamed only when no other issue custom field already has that name.
class StandardStoryPointFieldNames < ActiveRecord::Migration[5.2]
  NAMES = {
    'size_be_cfid' => 'Size - Backend', 'size_fe_cfid' => 'Size - Frontend', 'size_qa_cfid' => 'Size - QA',
    'story_point_cfid' => 'Size - Total',
    'sp_be_cfid' => 'Sprint SP - Backend', 'sp_fe_cfid' => 'Sprint SP - Frontend', 'sp_qa_cfid' => 'Sprint SP - QA',
    'sp_sprint_total_cfid' => 'Sprint SP - Total'
  }.freeze

  def up
    store = Setting.plugin_sanan_redmine_agile
    return unless store.is_a?(Hash)

    configs = store.values.select { |v| v.is_a?(Hash) }
    NAMES.each do |key, name|
      ids = configs.map { |c| c[key].to_i }.select(&:positive?).uniq
      next unless ids.size == 1 # one field per role everywhere, else keep the names as they are

      field = IssueCustomField.find_by(id: ids.first)
      next if field.nil? || field.name == name
      next if IssueCustomField.where(name: name).where.not(id: field.id).exists?

      field.update_column(:name, name)
    end
  end

  def down
    # Names are labels only; nothing to restore.
  end
end
