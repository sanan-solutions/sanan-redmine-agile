# frozen_string_literal: true

# Quarterly Product Roadmap: Epics placed per quarter, Story execution drill-down.
class RoadmapsController < ApplicationController
  unloadable
  before_action :find_project_by_project_id
  before_action :find_project_settings
  # The project Roadmap tab needs the setting; planning endpoints are also used from the portfolio page.
  before_action :ensure_roadmap_enabled, only: [:show, :data]
  before_action :authorize
  before_action :authorize_manage, only: [:move, :update_health, :update_span, :create_baseline, :destroy_baseline]
  before_action :find_epic, only: [:move, :update_health, :update_span, :update_priority]

  def show
    @year = parse_year(params[:year]) || Date.today.year
    @data = roadmap_data(@year)
  end

  # JSON refresh after an issue is created/edited in the global modal.
  def data
    render json: roadmap_data(parse_year(params[:year]) || Date.today.year)
  end

  # Moves an Epic into (year, quarter) — or back to Unplanned when quarter is blank/0 —
  # then rewrites positions of the target column from ordered_ids.
  def move
    quarter = params[:quarter].to_i
    item = SananRoadmapItem.find_or_initialize_by(issue_id: @epic.id)
    from = item.new_record? ? [nil, nil] : [item.year, item.quarter]

    if quarter.zero?
      SananRoadmapItem.transaction do
        item.destroy! if item.persisted?
        record_move!(from, [nil, nil])
      end
      return render json: { ok: true }
    end

    year = parse_year(params[:year])
    return render_error_json(l(:error_sanan_roadmap_invalid_quarter)) unless year && (1..4).cover?(quarter)

    span = item.persisted? ? item.span : 1
    item.project_id = @project.id
    item.year = year
    item.quarter = quarter
    item.span = span # a multi-quarter Epic keeps its length when moved
    item.health ||= 'on_track'
    SananRoadmapItem.transaction do
      item.save!
      persist_positions!(year, quarter, params[:ordered_ids])
      record_move!(from, [year, quarter])
    end
    render json: { ok: true }
  rescue ActiveRecord::RecordInvalid => e
    render_error_json(e.record.errors.full_messages.first)
  end

  # Epic priority, edited on the card / drawer. Goes through the issue's safe attributes and journal, as
  # the issue form does.
  def update_priority
    priority = IssuePriority.active.find_by(id: params[:priority_id])
    return render_error_json(l(:error_sanan_roadmap_priority_invalid)) unless priority
    unless @epic.safe_attribute?('priority_id') && !@epic.priority_derived?
      return render_error_json(l(:error_sanan_roadmap_priority_forbidden), :forbidden)
    end

    @epic.init_journal(User.current)
    @epic.safe_attributes = { 'priority_id' => priority.id.to_s }
    if @epic.save
      render json: { ok: true, priority_id: priority.id, priority: priority.name,
                     priority_key: SananAgile::PriorityIcon.key(priority) }
    else
      render_error_json(@epic.errors.full_messages.first)
    end
  rescue ActiveRecord::StaleObjectError
    render_error_json(l(:notice_issue_update_conflict), :conflict)
  end

  # Number of quarters the Epic spans, from its start quarter (1..4).
  def update_span
    item = SananRoadmapItem.find_by(issue_id: @epic.id)
    return render_error_json(l(:error_sanan_roadmap_not_planned)) unless item

    item.span = params[:span]
    if item.save
      render json: { ok: true, span: item.span }
    else
      render_error_json(item.errors.full_messages.first)
    end
  end

  # Locks the Epics currently planned in (year, quarter) as that quarter's baseline (re-run = re-baseline).
  def create_baseline
    year = parse_year(params[:year])
    quarter = params[:quarter].to_i
    return render_error_json(l(:error_sanan_roadmap_invalid_quarter)) unless year && (1..4).cover?(quarter)

    baseline = SananAgile::RoadmapBaseline.capture!(@project, year: year, quarter: quarter, user: User.current, cfg: @settings)
    render json: { ok: true, id: baseline.id }
  end

  def destroy_baseline
    SananRoadmapBaseline.where(project_id: @project.id, year: parse_year(params[:year]), quarter: params[:quarter].to_i)
                        .destroy_all
    render json: { ok: true }
  end

  def update_health
    item = SananRoadmapItem.find_by(issue_id: @epic.id)
    return render_error_json(l(:error_sanan_roadmap_not_planned)) unless item

    item.health = params[:health].to_s
    if item.save
      render json: { ok: true, health: item.health_key }
    else
      render_error_json(item.errors.full_messages.first)
    end
  end

  private

  def find_project_settings
    @settings = SananAgile::ProjectSettings.load(@project.id) || {}
  end

  def ensure_roadmap_enabled
    return if @settings['sanan_agile_enabled'].to_s == '1' && @settings['roadmap_enabled'].to_s == '1'

    render_404
  end

  def authorize_manage
    return true if User.current.allowed_to?(:manage_roadmap, @project)

    render_403
  end

  def find_epic
    @epic = Issue.visible
                 .where(project_id: @project.id, tracker_id: @settings['epic_tracker'].to_i)
                 .find_by(id: params[:issue_id])
    render_error_json(l(:error_sanan_roadmap_epic_not_found), :not_found) unless @epic
  end

  def roadmap_data(year)
    SananAgile::RoadmapProduct.board([@project], year: year)
  end

  # History row + issue journal note when the Epic changes quarter (reordering inside a quarter is ignored).
  # The journal is silent (no notification e-mail) and bypasses issue validations/callbacks.
  # Consecutive moves of the same Epic by the same user within MERGE_WINDOW are merged into one
  # (start of the first → end of the last); a sequence that ends where it started leaves no trace.
  def record_move!(from, to)
    return if from == to

    last = SananRoadmapMove.where(issue_id: @epic.id).order(:created_at, :id).last
    if last && last.user_id == User.current.id && last.created_at > SananRoadmapMove::MERGE_WINDOW.ago &&
       [last.to_year, last.to_quarter] == from
      from = [last.from_year, last.from_quarter]
      journal = Journal.find_by(id: last.journal_id)
      if from == to
        journal&.destroy
        last.destroy
        return
      end
      if journal
        journal.update_column(:notes, move_note(from, to))
      else
        journal = write_move_journal(from, to)
      end
      return last.update!(to_year: to[0], to_quarter: to[1], journal_id: journal.id)
    end

    journal = write_move_journal(from, to)
    SananRoadmapMove.create!(project_id: @project.id, issue_id: @epic.id, user_id: User.current.id,
                             from_year: from[0], from_quarter: from[1], to_year: to[0], to_quarter: to[1],
                             journal_id: journal.id, created_at: Time.now)
  end

  def write_move_journal(from, to)
    journal = Journal.new(journalized: @epic, user: User.current, notes: move_note(from, to))
    journal.notify = false
    journal.save!
    journal
  end

  def move_note(from, to)
    unplanned = l(:label_sanan_roadmap_unplanned)
    l(:text_sanan_roadmap_move_journal,
      from: SananRoadmapMove.label(*from) || unplanned, to: SananRoadmapMove.label(*to) || unplanned)
  end

  def persist_positions!(year, quarter, ordered_ids)
    ids = Array(ordered_ids).map(&:to_i).reject(&:zero?)
    return if ids.empty?

    items = SananRoadmapItem.where(project_id: @project.id, year: year, quarter: quarter, issue_id: ids).index_by(&:issue_id)
    ids.each_with_index do |id, idx|
      item = items[id]
      item.update_column(:position, idx) if item && item.position != idx
    end
  end

  def parse_year(val)
    y = val.to_s.strip
    return nil unless y.match?(/\A\d{4}\z/)

    y.to_i
  end

  def render_error_json(msg, status = :unprocessable_entity)
    render json: { ok: false, error: msg }, status: status
  end
end
