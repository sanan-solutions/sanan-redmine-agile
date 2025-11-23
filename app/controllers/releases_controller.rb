# app/controllers/releases_controller.rb
class ReleasesController < ApplicationController
  unloadable
  before_action :find_project
  before_action :find_project_settings
  before_action :ensure_sanan_agile_enabled
  before_action :authorize
  before_action :find_release, only: [:show, :attach_issues, :detach_item, :reorder,
                                      :update_issue_status, :change_state, :issue_panel, :edit, :update]

  # GET /projects/:project_id/releases
  def index
    scope = ::ReleaseVersion.where(project_id: @project.id)

    # lọc theo trạng thái (tùy chọn)
    case params[:state].to_s
    when 'released'   then scope = scope.where(state: 'released')
    when 'unreleased' then scope = scope.where(state: 'unreleased')
    when 'archived'   then scope = scope.where(state: 'archived')
    end

    # search theo tên (tùy chọn)
    if params[:q].present?
      scope = scope.where('LOWER(name) LIKE ?', "%#{params[:q].to_s.downcase}%")
    end

    scope = scope.order(created_at: :desc)

    @per_page       = 20
    @releases_count = scope.count
    @releases_pages = Paginator.new @releases_count, @per_page, params[:page]
    @releases       = scope.limit(@releases_pages.per_page).offset(@releases_pages.offset)
  end

  def new
    render layout: false
  end

  def create
    rel = ReleaseVersion.new(
      project: @project,
      name: params[:name],
      start_on: params[:start_on],
      release_on: params[:release_on],
      description: params[:description],
      release_notes_url: params[:release_notes_url]
    )
    if rel.save
      Array(params[:driver_ids]).reject(&:blank?).map(&:to_i).each do |uid|
        rel.release_version_drivers.create!(user_id: uid)
      end
      render json: { ok: true, id: rel.id, url: project_release_path(@project, rel) }
    else
      render json: { ok: false, errors: rel.errors.full_messages }, status: 422
    end
  end

  def show
    can_add_child_issue_standard   = @settings['release_add_child_issue_standard_tracker'].to_s == '1'
    standard_ids    = Array(@settings['standard_tracker']).map(&:to_i).presence
    open_status_ids = IssueStatus.where(is_closed: false).pluck(:id)
    all_issue_status_ids =IssueStatus.pluck(:id)

    # 🚨 Kiểm tra cấu hình bắt buộc
    if standard_ids.blank?
      render json: {
        error: true,
        message: "⚠️ Please configure Tracker type in Project Settings for using release."
      }, status: :bad_request and return
    end

    # 1) Cha: các issue được pick vào release (release_items)
    @issues = @release.issues
                            .visible(User.current)
                            .where(status_id: all_issue_status_ids)
                            .includes(:status, :tracker, :assigned_to, :priority, :parent)

    parent_ids = @issues.map(&:id)

    # 2) Child: con trực thuộc các parent (nếu cấu hình cho phép)
    if !can_add_child_issue_standard
      @child_issues = Issue.visible(User.current)
                          .where(status_id: open_status_ids, parent_id: parent_ids)
                          .includes(:status, :tracker, :assigned_to, :priority, :parent)
      @children_by_parent = @child_issues.group_by(&:parent_id)
    else
      @child_issues = []
      @children_by_parent = {}
    end

    @statuses   = IssueStatus.sorted.to_a
    # @trackers   = Tracker.sorted.to_a
    # @priorities = (IssuePriority.respond_to?(:active) ? IssuePriority.active : IssuePriority).sorted.to_a

    # settings = SananAgile::ProjectSettings.load(@project.id)

      # ===== ONLY PARENTS =====
    dev_done_cfid = @settings['development_done_cfid'].to_i
    @from_sprint_by_issue = {}
    if dev_done_cfid.positive? && parent_ids.any?
      cv_pairs     = CustomValue.where(customized_type: 'Issue',
                                      custom_field_id: dev_done_cfid,
                                      customized_id: parent_ids)
                                .pluck(:customized_id, :value)
      ver_ids      = cv_pairs.map { |_, v| v.to_i }.reject(&:zero?).uniq
      ver_name_map = Version.where(id: ver_ids).pluck(:id, :name).to_h
      @from_sprint_by_issue = cv_pairs.each_with_object({}) do |(iid, val), h|
        vid  = val.to_i
        name = ver_name_map[vid]
        h[iid] = [vid, name] if vid.positive? && name.present?
      end
    end

    @progress = @release.progress
  end

  def edit
    if request.xhr?
      render layout: false
    else
      redirect_to project_release_path(@project, @release)
    end
  end
  
  def update
    @release.assign_attributes(
      name: params[:name],
      start_on: params[:start_on],
      release_on: params[:release_on],
      description: params[:description],
      release_notes_url: params[:release_notes_url]
    )
    if @release.save
      # cập nhật drivers
      if params.key?(:driver_ids)
        @release.release_version_drivers.delete_all
        Array(params[:driver_ids]).reject(&:blank?).map(&:to_i).each do |uid|
          @release.release_version_drivers.create!(user_id: uid)
        end
      end
      render json: { ok: true }
    else
      render json: { ok: false, errors: @release.errors.full_messages }, status: 422
    end
  end

  # --- data source cho picker
  def issues_search
    q     = params[:q].to_s.strip
    current_release_id   = params[:exclude_release_id]

    allowed_status_ids = Array(@settings['release_status_filter_ids']).map(&:to_i)
    epic_tracker_id = @settings['epic_tracker'].presence.to_i if @settings['epic_tracker'].present?
    standard_ids    = Array(@settings['standard_tracker']).map(&:to_i).presence
    can_add_child_issue_standard   = @settings['release_add_child_issue_standard_tracker'].to_s == '1'
    dev_done_cfid   = @settings['development_done_cfid'].to_i # <— CF id

    # 🚨 Kiểm tra cấu hình bắt buộc
    if epic_tracker_id.blank? || standard_ids.blank?
      render json: {
        error: true,
        message: "⚠️ Please configure Tracker type in Project Settings for using release."
      }, status: :bad_request and return
    end

    open_status_ids = IssueStatus.where(is_closed: false).pluck(:id)
    
    scope = Issue.visible(User.current)
      .where(project_id: @project.id)
      .where(status_id: open_status_ids)
    scope = scope.where(status_id: allowed_status_ids) if allowed_status_ids.present?

    # Eager load để tránh N+1 ở tracker/priority/status/assignee
    scope = scope.includes(:tracker, :priority, :status, :assigned_to)

    # Chỉ lấy work items thuộc "standard trackers"
    scope = scope.where(tracker_id: standard_ids) if standard_ids.present?

    # Join cha để có thể lọc & render epic mà không N+1
    scope = scope.left_outer_joins(:parent)

    # Nếu bật “standard child must have epic parent”, ép điều kiện:
    #  - Không có cha OR cha có tracker = epic_tracker
    logger.info "dattestne: #{!can_add_child_issue_standard}"
    if !can_add_child_issue_standard && epic_tracker_id.present?
      scope = scope.where("issues.parent_id IS NULL OR parents_issues.tracker_id = ?", epic_tracker_id)
    end

    # Join release để biết issue đang nằm ở release nào
    scope = scope.left_outer_joins(release_item: :release_version)
               .select(
                 'issues.*',
                 'release_items.release_version_id AS release_id',
                 'release_versions.name             AS release_name',
                 # cột của cha để build badge epic
                 'parents_issues.id       AS epic_id',
                 'parents_issues.subject  AS epic_subject',
                 'parents_issues.tracker_id AS epic_tracker'
               )

    # join custom_values (dev-done-in-sprint = Version)
    if dev_done_cfid.positive?
      scope = scope
        .joins(
          ActiveRecord::Base.send(
            :sanitize_sql_array,
            [
              "LEFT JOIN custom_values cv_dev
                ON cv_dev.customized_type='Issue'
                AND cv_dev.customized_id=issues.id
                AND cv_dev.custom_field_id=?",
              dev_done_cfid
            ]
          )
        )
        .joins("LEFT JOIN versions v_dev ON CAST(cv_dev.value AS UNSIGNED)=v_dev.id")
        .select('v_dev.id AS devdone_version_id, v_dev.name AS devdone_version_name')
    end

    if q.present?
      pattern = "%#{q.downcase}%"
      scope = scope.where('LOWER(issues.subject) LIKE ? OR CAST(issues.id AS CHAR) LIKE ?', pattern, "%#{q.gsub('#','')}%")
    end
    scope = scope.where(status_id: params[:status_id]) if params[:status_id].present?

    scope = scope
    # .left_joins(:parent) # để có parent_id nếu cần
    # .order(Arel.sql("COALESCE(issues.parent_id, issues.id) DESC"))
    .order(priority_id: :desc)
    .order(id: :desc)

    render json: scope.map{ |i|
      release_id   = i.read_attribute('release_id')
      release_name = i.read_attribute('release_name')
      p_epic_id     = i.read_attribute('epic_id')
      p_epic_name   = i.read_attribute('epic_subject')
      p_epic_track  = i.read_attribute('epic_tracker')

      epic_label = if p_epic_id.present? && epic_tracker_id.present? && p_epic_track.to_i == epic_tracker_id
        "##{p_epic_id}: #{p_epic_name}"
      end
  
      { 
        id:          i.id,
        key:         "##{i.id}",
        subject:     i.subject,
        epic:         epic_label,
        status:      i.status&.name,
        tracker:     i.tracker&.name,
        priority:    i.priority&.name,
        assignee:    i.assigned_to&.name,
        release_id:   release_id,      # nil nếu chưa thuộc release nào
        release_name:      release_name,    # nil nếu chưa thuộc
        in_current_release: current_release_id.present? && release_id.to_i == current_release_id.to_i,
        from_sprint_id:   i.read_attribute('devdone_version_id'),
        from_sprint_name: i.read_attribute('devdone_version_name')
      }
    }
  end

  def attach_issues
    ids = Array(params[:issue_ids]).map(&:to_i).uniq

    ReleaseItem.transaction do
      ids.each do |iid|
        # nếu issue đang gắn ở release khác → move sang release hiện tại
        ri = ReleaseItem.find_or_initialize_by(issue_id: iid)
        ri.release_version_id = @release.id
        ri.added_at  ||= Time.current
        ri.added_by_id ||= User.current.id
        ri.save!  # unique index sẽ đảm bảo 1-1
      end
    end
  
    render json: { ok: true }
  end

  def detach_item
    @release.items.find_by!(issue_id: params[:issue_id]).destroy
    head :ok
  end

  def reorder
    # params[:order] = [{issue_id:1, position:1}, ...]
    ReleaseItem.transaction do
      params[:order].each do |row|
        @release.items.where(issue_id: row[:issue_id]).update_all(position: row[:position])
      end
    end
    head :ok
  end

  def update_issue_status
    issue = Issue.visible(User.current).find(params[:issue_id])
    new_status = IssueStatus.find(params[:status_id])
    issue.init_journal(User.current, '[release quick update]')
    issue.status = new_status
    if issue.save
      render json: { ok: true }
    else
      render json: { ok: false, errors: issue.errors.full_messages }, status: 422
    end
  end

  def change_state
    @release.assign_attributes(state: params[:state])
    if @release.save
      render json: { ok: true, state: @release.state }
    else
      render json: {
        ok: false,
        message: @release.errors.full_messages.uniq.join('. '),
        errors: @release.errors.to_hash(true)
      }, status: :unprocessable_entity
    end
  end

  def issue_panel
    @issue = Issue.visible(User.current).find(params[:issue_id])
    render partial: 'releases/issue_panel', layout: false
  end

  private
  def find_project ; @project = Project.find(params[:project_id]) ; end
  def find_release ; @release = ReleaseVersion.find(params[:id]) ; end
  def find_project_settings ; @settings = SananAgile::ProjectSettings.load(@project&.id) || {}; end
  def ensure_sanan_agile_enabled
    return if @settings['sanan_agile_enabled'].to_s == '1'
  
    render_404
  end
end
