# app/controllers/sanan_agile/release_badges_controller.rb
class ReleaseBadgesController < ApplicationController
  before_action :find_project
  before_action :require_login
  accept_api_auth :unreleased_map

  # Trả về:
  # [{ issue_id: 123, releases: [{id: 7, name: "R 2025.11"}, ...] }, ...]
  # Bao gồm cả:
  # - Issues là parent đã link vào ReleaseVersion.state = 'unreleased'
  # - Con trực tiếp của các parent đó, với tracker thuộc "standard_tracker"
  def unreleased_map
    cfg           = SananAgile::ProjectSettings.load(@project.id)
    standard_ids  = Array(cfg['standard_tracker']).map(&:to_i).reject(&:zero?)

    # 1) Lấy các (parent_issue_id, rv_id, rv_name) cho release "unreleased"
    rows = ReleaseItem.joins(:release_version)
                      .where(release_versions: { project_id: @project.id, state: 'unreleased' })
                      .select('release_items.issue_id AS parent_id',
                              'release_versions.id AS rv_id',
                              'release_versions.name AS rv_name')
                      .to_a

    if rows.empty?
      return render json: []
    end

    # Mapping parent -> releases
    parent_to_releases = {}
    rows.each do |r|
      parent_to_releases[r.parent_id] ||= []
      parent_to_releases[r.parent_id] << { id: r.rv_id, name: r.rv_name }
    end

    # 2) Lấy children (1 cấp) thuộc standard tracker
    child_pairs = []
    if standard_ids.present?
      child_pairs = Issue.where(parent_id: parent_to_releases.keys, tracker_id: standard_ids)
                         .pluck(:id, :parent_id) # [ [child_id, parent_id], ... ]
    end

    # 3) Build payload cho cả parent & child (child thừa hưởng các releases của parent)
    out = []

    parent_to_releases.each do |pid, releases|
      out << { issue_id: pid, releases: releases.uniq { |x| x[:id] } }
    end

    child_pairs.each do |child_id, parent_id|
      releases = parent_to_releases[parent_id] || []
      next if releases.empty?
      out << { issue_id: child_id, releases: releases.uniq { |x| x[:id] } }
    end

    render json: out
  end

  private

  def find_project
    @project = Project.find(params[:project_id])
  end
end
