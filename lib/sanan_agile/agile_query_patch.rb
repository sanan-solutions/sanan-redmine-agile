# frozen_string_literal: true

# Agile board query helpers: hidden trackers (applied in AgileQuery#statement via
# SananAgile::AgileQueryAssociationPatch) and the Target version filter.
module SananAgile
  module AgileQueryPatch
    module_function

    def hidden_tracker_ids_for(project)
      return [] unless project

      cfg = SananAgile::ProjectSettings.load(project.id)
      return [] unless cfg['sanan_agile_enabled'].to_s == '1'

      Array(cfg['agile_board_hidden_tracker_ids']).map(&:to_i).reject(&:zero?).uniq
    end

    # Target version filter on the board: closed sprints are left out (a value already selected stays).
    def hide_closed_versions!(query, filters)
      filter = filters && filters['fixed_version_id']
      project = query.project
      return unless filter && project
      return unless SananAgile::ProjectSettings.load(project.id)['sanan_agile_enabled'].to_s == '1'

      closed = project.shared_versions.where(status: 'closed').pluck(:id).map(&:to_s).to_set
      return if closed.empty?

      all_values = Array(filter[:values])
      # Evaluated when the filter is rendered, after the query's own filters are set (remote: false keeps
      # it inline instead of an AJAX lookup on a fresh query).
      values = lambda do
        selected = Array(query.filters.to_h.dig('fixed_version_id', :values)).map(&:to_s)
        all_values.reject { |_label, id| closed.include?(id.to_s) && !selected.include?(id.to_s) }
      end
      query.add_available_filter('fixed_version_id', type: filter[:type], values: values, remote: false)
    end
  end
end
