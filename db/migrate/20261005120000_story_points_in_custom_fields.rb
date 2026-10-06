# frozen_string_literal: true

# Story points move to issue custom fields only (SananAgile::IssueSp):
#   Size BE / FE / QA  — were rows of sanan_issue_sp_sizes          → new fields "Size - Backend / Frontend / QA";
#   Size Total         — stays in story_point_cfid;
#   Sprint BE / FE / QA — stay in sp_be_cfid / sp_fe_cfid / sp_qa_cfid;
#   Sprint Total       — was the current sprint's row of sanan_issue_sprint_sps → new field "Sprint SP - Total";
#   sub-task personal SP — was story_point_cfid                    → the sprint Total field (per sprint).
# sanan_issue_sprint_sps keeps only the history of the sprints a ticket left. The new fields are created once,
# for the whole Redmine, and set in the global settings (projects inherit them).
class StoryPointsInCustomFields < ActiveRecord::Migration[5.2]
  KEY = :sanan_redmine_agile
  NEW_FIELDS = {
    'size_be_cfid' => 'Size - Backend',
    'size_fe_cfid' => 'Size - Frontend',
    'size_qa_cfid' => 'Size - QA',
    'sp_sprint_total_cfid' => 'Sprint SP - Total'
  }.freeze

  def up
    store = Setting.send(:"plugin_#{KEY}")
    store = {} unless store.is_a?(Hash)
    projects = store.reject { |k, v| k == '_global' || !v.is_a?(Hash) }
    global = (store['_global'] || {}).dup

    like = (projects.values + [global]).flat_map { |c| %w[story_point_cfid sp_be_cfid sp_fe_cfid sp_qa_cfid].map { |k| c[k].to_i } }
                                       .select(&:positive?).uniq
    # The sprint Total is also the personal SP of sub-tasks: enable it for the sub-task trackers too.
    subtask_trackers = (projects.values + [global]).flat_map { |c| Array(c['subtask_tracker']).map(&:to_i) }.select(&:positive?)
    NEW_FIELDS.each do |key, name|
      next if global[key].to_i.positive?

      extra = key == 'sp_sprint_total_cfid' ? subtask_trackers : []
      global[key] = find_or_create_field(name, like, extra).id.to_s
    end
    store['_global'] = global
    # A project holding these keys blank would hide the new fields: let it follow the global settings.
    projects.each do |project_id, cfg|
      store[project_id] = cfg.reject { |k, v| NEW_FIELDS.key?(k) && v.to_s.strip.empty? }
    end
    Setting.send(:"plugin_#{KEY}=", JSON.parse(store.to_json))

    projects.each_key { |project_id| migrate_project(project_id.to_i) }
  end

  def down
    # Data stays in the custom fields; nothing to restore.
  end

  private

  def find_or_create_field(name, like_ids, extra_trackers = [])
    existing = IssueCustomField.find_by(name: name)
    return existing if existing

    likes = IssueCustomField.where(id: like_ids).to_a
    field = IssueCustomField.new(name: name, field_format: 'float', is_required: false, is_filter: true,
                                 searchable: false, visible: true, editable: true)
    trackers = (likes.flat_map(&:tracker_ids) + extra_trackers).uniq
    field.tracker_ids = trackers.presence || Tracker.pluck(:id)
    if likes.empty? || likes.any?(&:is_for_all)
      field.is_for_all = true
    else
      field.project_ids = likes.flat_map(&:project_ids).uniq
    end
    field.save!
    field
  end

  def migrate_project(project_id)
    cfg = SananAgile::ProjectSettings.load(project_id)
    issue_ids = Issue.where(project_id: project_id).pluck(:id)
    return if issue_ids.empty?

    copy_sizes(cfg, issue_ids)
    copy_current_sprint_totals(cfg, issue_ids)
    move_personal_sp(cfg, project_id)
  end

  def copy_sizes(cfg, issue_ids)
    return unless table_exists?(:sanan_issue_sp_sizes)

    ids = { 'sp_be' => cfg['size_be_cfid'], 'sp_fe' => cfg['size_fe_cfid'], 'sp_qa' => cfg['size_qa_cfid'] }
    select_rows("SELECT issue_id, sp_be, sp_fe, sp_qa FROM sanan_issue_sp_sizes WHERE issue_id IN (#{issue_ids.join(',')})")
      .each do |issue_id, *values|
        ids.values.zip(values).each { |cfid, value| write_value(issue_id, cfid, value) }
      end
  end

  # The row of the sprint a ticket is on held its current sprint Total: it becomes the field value; the
  # history table keeps only the sprints the ticket left.
  def copy_current_sprint_totals(cfg, issue_ids)
    cfid = cfg['sp_sprint_total_cfid'].to_i
    return unless cfid.positive?

    current = Issue.where(id: issue_ids).where.not(fixed_version_id: nil).pluck(:id, :fixed_version_id).to_h
    SananIssueSprintSp.where(issue_id: current.keys).find_each do |row|
      next unless current[row.issue_id] == row.version_id

      write_value(row.issue_id, cfid, row.sp_total) unless row.sp_total.nil?
      row.destroy
    end
  end

  # Sub-tasks kept their personal SP in story_point_cfid (now Size Total): it moves to the sprint Total.
  def move_personal_sp(cfg, project_id)
    from = cfg['story_point_cfid'].to_i
    to = cfg['sp_sprint_total_cfid'].to_i
    return unless from.positive? && to.positive? && from != to

    trackers = Tracker.pluck(:id).select do |tid|
      SananAgile::SpTotalFormula.subtask?(Issue.new(tracker_id: tid), cfg)
    end
    return if trackers.empty?

    ids = Issue.where(project_id: project_id, tracker_id: trackers).pluck(:id)
    CustomValue.where(customized_type: 'Issue', customized_id: ids, custom_field_id: from).find_each do |cv|
      write_value(cv.customized_id, to, cv.value) if cv.value.present?
      cv.destroy
    end
  end

  def write_value(issue_id, cfid, value)
    cfid = cfid.to_i
    return unless cfid.positive?

    text = SananAgile::IssueSp.format(value)
    return if text.empty?

    cv = CustomValue.find_or_initialize_by(customized_type: 'Issue', customized_id: issue_id, custom_field_id: cfid)
    return if cv.persisted? && cv.value.present? # never overwrite a value already in the field

    cv.value = text
    cv.save!(validate: false)
  end
end
