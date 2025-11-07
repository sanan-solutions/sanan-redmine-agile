# app/models/release_item.rb
class ReleaseItem < ActiveRecord::Base
  self.table_name = 'release_items'
  belongs_to :release_version
  belongs_to :issue

  belongs_to :added_by, class_name: 'User', optional: true

  acts_as_list scope: :release_version_id
  validates :issue_id, :release_version_id, presence: true

  # CHỐT HIỆN TẠI: 1 issue chỉ thuộc 1 release
  # (Khi muốn mở rộng nhiều release trong tương lai -> chỉ cần xoá dòng dưới và drop unique index issue_id)
  validates :issue_id, uniqueness: true

  # Chống add trùng 1 issue 2 lần vào cùng 1 release
  validates :issue_id, uniqueness: { scope: :release_version_id }

  # Tự set thời điểm/người thêm khi create
  before_validation :set_added_meta, on: :create

  private

  def set_added_meta
    self.added_at   ||= Time.current
    # Nếu bạn đang gọi từ controller với User.current:
    self.added_by_id ||= (User.current&.id rescue nil)
  end
end