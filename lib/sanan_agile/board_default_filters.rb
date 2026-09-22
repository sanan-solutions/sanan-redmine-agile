# frozen_string_literal: true

module SananAgile
  module BoardDefaultFilters
    module_function

    def apply!(query)
      return unless defined?(AgileQuery) && query.is_a?(AgileQuery)
      return if query.persisted?
      project = query.project
      return unless project

      version = project.default_version
      return unless version

      query.filters ||= {}
      current = query.filters['fixed_version_id'] || query.filters[:fixed_version_id]
      existing = Array(current && (current[:values] || current['values'])).map(&:to_s).reject(&:blank?)
      return if existing.any?

      query.instance_variable_set(:@available_filters, nil)
      query.available_filters
      unless query.available_filters.key?('fixed_version_id')
        query.add_available_filter(
          'fixed_version_id',
          type: :list_optional,
          values: [["#{version.project&.name} - #{version.name}", version.id.to_s]]
        )
      end
      query.filters['fixed_version_id'] = { operator: '=', values: [version.id.to_s] }
    end
  end
end
