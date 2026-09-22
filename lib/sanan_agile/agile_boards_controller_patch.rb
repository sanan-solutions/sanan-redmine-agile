# frozen_string_literal: true

module SananAgile
  module AgileBoardsControllerPatch
    def index
      SananAgile::AgileStoryPoints.install!
      return if sanan_redirect_to_active_version_filter
      super
    end

    def update
      SananAgile::AgileStoryPoints.install!
      super
    end

    def retrieve_agile_query
      super
      SananAgile::BoardDefaultFilters.apply!(@query)
    end

    private

    def sanan_redirect_to_active_version_filter
      return false unless @project
      return false if params[:query_id].present?
      version = @project.default_version
      return false unless version
      return false if Array(params[:f]).any?(&:present?) || Array(params[:fields]).any?(&:present?)
      return false if sanan_session_has_version_filter?

      redirect_to(
        controller: 'agile_boards',
        action: 'index',
        project_id: @project.to_param,
        set_filter: 1,
        f: ['fixed_version_id'],
        op: { 'fixed_version_id' => '=' },
        v: { 'fixed_version_id' => [version.id.to_s] }
      )
      true
    end

    def sanan_session_has_version_filter?
      sess = session[:agile_query]
      return false unless sess && sess[:project_id].to_i == @project.id.to_i

      filters = sess[:filters]
      return false unless filters.is_a?(Hash)

      fv = filters['fixed_version_id'] || filters[:fixed_version_id]
      vals = fv && (fv[:values] || fv['values'])
      Array(vals).any?(&:present?)
    end
  end
end
