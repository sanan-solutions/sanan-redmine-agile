# app/models/release_version.rb
class ReleaseVersion < ActiveRecord::Base
  self.table_name = 'release_versions'

  belongs_to :project
  has_many :items,   class_name: 'ReleaseItem', dependent: :destroy
  has_many :issues,  through: :items

  has_many :release_version_drivers, dependent: :delete_all
  has_many :drivers, through: :release_version_drivers, source: :user

  validates :name, presence: true
  validates :release_notes_url, allow_blank: true,
            format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }

    # 1) Chặn đổi state nếu chưa thoả điều kiện
  before_update :validate_ready_to_release,
      if: -> { will_save_change_to_state? && state_change_to_be_saved&.last == 'released' }

  # 2) Sau khi sang released: force status (bypass workflow) cho parent + level1 (standard)
  after_update  :force_status_when_released,
      if: -> { saved_change_to_state? && state == 'released' }

  # def progress(done_status_ids: nil)
  #   scope = issues
  #   return 0 if scope.empty?
  #   done_ids = Array(done_status_ids).presence || IssueStatus.where(is_closed: true).pluck(:id)
  #   ((scope.where(status_id: done_ids).count.to_f / scope.count) * 100).round
  # end

  def progress(include_children: false)
    scope = issues # chỉ các issue được attach vào release qua release_items
  
    return 0 if scope.empty?
  
    if include_children
      parent_ids  = scope.pluck(:id)
      child_ids   = Issue.where(parent_id: parent_ids).pluck(:id)
      scope       = Issue.where(id: parent_ids + child_ids)
    end
  
    # AVG(done_ratio) trả về BigDecimal hoặc nil
    scope.average(:done_ratio).to_f.round
  end

  # Release gắn trực tiếp qua release_items; issue con (standard tracker) kế thừa từ cha.
  def self.for_issue(issue)
    return nil unless issue&.id

    cached = issue.instance_variable_get(:@sanan_release_version_cache)
    return nil if cached == :none
    return cached if cached

    rv = resolve_for_issue(issue)
    issue.instance_variable_set(:@sanan_release_version_cache, rv || :none)
    rv
  end

  # Preload release mapping for issue lists (avoids N+1).
  def self.preload_for_issues!(issues)
    issues = Array(issues).compact
    return if issues.empty?

    ids = issues.map(&:id)
    parent_ids = issues.map(&:parent_id).compact.uniq
    map = ReleaseItem.includes(:release_version)
                     .where(issue_id: (ids + parent_ids).uniq)
                     .each_with_object({}) { |ri, h| h[ri.issue_id] = ri.release_version }

    issues.each do |issue|
      rv = map[issue.id]
      if rv.nil? && issue.parent_id
        cfg = SananAgile::ProjectSettings.load(issue.project_id)
        standard_ids = Array(cfg['standard_tracker']).map(&:to_i).reject(&:zero?)
        rv = map[issue.parent_id] if standard_ids.include?(issue.tracker_id.to_i)
      end
      issue.instance_variable_set(:@sanan_release_version_cache, rv || :none)
    end
  end

  def self.resolve_for_issue(issue)
    if issue.association(:release_item).loaded?
      rv = issue.release_version
      return rv if rv
    else
      item = ReleaseItem.includes(:release_version).find_by(issue_id: issue.id)
      return item.release_version if item&.release_version
    end

    return nil unless issue.parent_id

    cfg = SananAgile::ProjectSettings.load(issue.project_id)
    standard_ids = Array(cfg['standard_tracker']).map(&:to_i).reject(&:zero?)
    return nil if standard_ids.blank? || !standard_ids.include?(issue.tracker_id.to_i)

    if issue.association(:parent).loaded? && issue.parent
      return for_issue(issue.parent) if issue.parent.association(:release_item).loaded?
    end

    parent_item = ReleaseItem.includes(:release_version).find_by(issue_id: issue.parent_id)
    parent_item&.release_version
  end
  private_class_method :resolve_for_issue

  private

  # ---------- Scopes (chỉ là subquery, không load record) ----------
  def parents_scope
    # Các issue đã pick vào release
    issues.select(:id)
  end

  def level1_scope
    Issue.where(parent_id: parents_scope).select(:id)
  end

  def level2_scope
    Issue.where(parent_id: level1_scope).select(:id)
  end

  def open_status_ids_rel
    IssueStatus.where(is_closed: false).select(:id)  # subquery dùng trong WHERE
  end

  def close_status_ids_rel
    IssueStatus.where(is_closed: true).select(:id)  # subquery dùng trong WHERE
  end

  # ---------- VALIDATION: nhanh & ít query ----------
  def validate_ready_to_release
    cfg             = SananAgile::ProjectSettings.load(project_id)
    standard_ids    = Array(cfg['standard_tracker']).map(&:to_i).reject(&:zero?)
    subtask_ids     = Array(cfg['subtask_tracker']).map(&:to_i).reject(&:zero?)
    required_status_id = cfg['release_released_status_id'].to_i
    released_status_id   = cfg['release_close_status_id'].to_i      # status sẽ set sau khi release
    issue_status_id_valid = ([required_status_id, released_status_id]+ close_status_ids_rel.pluck(:id)).uniq

    # Thiếu cấu hình bắt buộc
    if required_status_id <= 0 || released_status_id <= 0 || standard_ids.blank?
      errors.add(:state, 'Missing project settings: standard trackers or required status')
      throw(:abort)
    end

    # (V1) Tồn tại level-1 subtask chưa close?
    if Issue.where(id: level1_scope)                        # level-1
            .where(tracker_id: subtask_ids)
            .where(status_id: open_status_ids_rel)
            .limit(1).exists?
      # Chỉ truy vấn nhẹ để liệt kê vài ID (không bắt buộc)
      bad = Issue.where(id: level1_scope)
                  .where(tracker_id: subtask_ids, status_id: open_status_ids_rel)
                  .limit(5).pluck(:id)
      errors.add(:state, "Open subtask at level-1: #{bad.join(', ')}")
      throw(:abort)
    end

    # (V2) Tồn tại level-2 subtask chưa close?
    if Issue.where(id: level2_scope)                        # level-2
            .where(tracker_id: subtask_ids)
            .where(status_id: open_status_ids_rel)
            .limit(1).exists?
      bad = Issue.where(id: level2_scope)
                  .where(tracker_id: subtask_ids, status_id: open_status_ids_rel)
                  .limit(5).pluck(:id)
      errors.add(:state, "Open subtask at level-2: #{bad.join(', ')}")
      throw(:abort)
    end

    # (V3) Parent + level-1 thuộc standard phải đang ở required_status
    wrong_parent_exists =
      Issue.where(id: parents_scope).where(tracker_id: standard_ids)
            .where.not(status_id: issue_status_id_valid)
            .limit(1).exists?

    wrong_l1_exists =
      Issue.where(id: level1_scope).where(tracker_id: standard_ids)
            .where.not(status_id: issue_status_id_valid)
            .limit(1).exists?

    if wrong_parent_exists || wrong_l1_exists
      bad_ids =
        Issue.where(id: parents_scope).where(tracker_id: standard_ids)
              .where.not(status_id: issue_status_id_valid).limit(10).pluck(:id) +
        Issue.where(id: level1_scope).where(tracker_id: standard_ids)
              .where.not(status_id: issue_status_id_valid).limit(10).pluck(:id)
      errors.add(:state, "Standard issues must be closed or at required status before release (IDs: #{bad_ids.uniq.join(', ')})")
      throw(:abort)
    end
  end

  # ---------- AFTER UPDATE: bypass workflow, cập nhật nhanh ----------
  def force_status_when_released
    cfg                  = SananAgile::ProjectSettings.load(project_id)
    standard_ids         = Array(cfg['standard_tracker']).map(&:to_i).reject(&:zero?)
    required_status_id   = cfg['release_released_status_id'].to_i   # status bắt buộc trước khi release
    released_status_id   = cfg['release_close_status_id'].to_i      # status sẽ set sau khi release
  
    # --- Guards
    if standard_ids.blank? || required_status_id <= 0 || released_status_id <= 0
      Rails.logger.warn "[sanan_agile] force_status_when_released skipped: bad settings "\
                        "(standard=#{standard_ids.inspect}, req=#{required_status_id}, rel=#{released_status_id})"
      return
    end
    if required_status_id == released_status_id
      Rails.logger.warn "[sanan_agile] force_status_when_released skipped: required_status == released_status (#{released_status_id})"
      return
    end
  
    # --- Subqueries: parent và level-1
    parents = issues.select(:id)                                  # đã pick vào release
    level1  = Issue.where(parent_id: parents).select(:id)         # con trực tiếp
  
    # Gộp tập IDs bằng một subquery 'IN (SELECT ... UNION ...)'
    # Cách portable: dùng OR giữa 2 relation cùng base, rồi bọc lại:
    ids_rel = Issue.where(id: parents).or(Issue.where(id: level1)).select(:id)
  
    # Chỉ các issue thuộc standard tracker, đang ở required_status (điều kiện bạn muốn),
    # và nằm trong (parents ∪ level1)
    scope = Issue.where(tracker_id: standard_ids, status_id: required_status_id)
                 .where(id: ids_rel)
  
    # Debug trước khi update
    count_before = scope.count
    Rails.logger.info "[sanan_agile] force_status_when_released candidates=#{count_before} "\
                      "(req=#{required_status_id} -> rel=#{released_status_id})"
  
    return if count_before.zero?
  
    # BYPASS workflow/journal
    updated = scope.update_all(status_id: released_status_id, updated_on: Time.current)
    Rails.logger.info "[sanan_agile] force_status_when_released updated_rows=#{updated}"
  rescue => e
    Rails.logger.error "[sanan_agile] force_status_when_released failed: #{e.class}: #{e.message}"
  end
end

# app/models/release_version_driver.rb
class ReleaseVersionDriver < ActiveRecord::Base
  self.table_name = 'release_version_drivers'
  belongs_to :release_version
  belongs_to :user
  validates :user_id, presence: true
end

class Issue < ActiveRecord::Base
  has_one  :release_item, dependent: :destroy
  has_one  :release_version, through: :release_item
end