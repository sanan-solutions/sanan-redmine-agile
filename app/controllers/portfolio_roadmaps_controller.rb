# frozen_string_literal: true

# Cross-product roadmap (not scoped to a project): one row per selected product.
# The selection is remembered per user and mirrored in the URL (project_ids[]).
class PortfolioRoadmapsController < ApplicationController
  unloadable
  PREF_KEY = :sanan_roadmap_project_ids

  before_action :require_login
  before_action :authorize_global_roadmap
  before_action :load_projects

  def show
    @year = parse_year(params[:year]) || Date.today.year
    @data = SananAgile::RoadmapProduct.board(@selected, year: @year)
  end

  def data
    render json: SananAgile::RoadmapProduct.board(@selected, year: parse_year(params[:year]) || Date.today.year)
  end

  private

  def authorize_global_roadmap
    return true if User.current.allowed_to?(:view_roadmap, nil, global: true)

    deny_access
  end

  # @available: products the user may see; @selected: the ones shown as rows.
  def load_projects
    @available = SananAgile::RoadmapProduct.available_projects
    ids = if params[:apply].present? || params.key?(:project_ids)
            save_selection(Array(params[:project_ids]))
          else
            stored_selection
          end
    @selected = ids.nil? ? @available : @available.select { |p| ids.include?(p.id) }
  end

  def stored_selection
    raw = User.current.pref[PREF_KEY]
    raw.nil? ? nil : Array(raw).map(&:to_i)
  end

  def save_selection(raw_ids)
    ids = raw_ids.map(&:to_i).reject(&:zero?) & @available.map(&:id)
    pref = User.current.pref
    pref[PREF_KEY] = ids
    pref.save
    ids
  end

  def parse_year(val)
    y = val.to_s.strip
    y.match?(/\A\d{4}\z/) ? y.to_i : nil
  end
end
