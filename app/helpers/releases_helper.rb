# frozen_string_literal: true

module ReleasesHelper
  RELEASE_SORT_COLUMNS = %w[name state progress start_on release_on description created_at].freeze

  def release_sort_th_class(column)
    return unless RELEASE_SORT_COLUMNS.include?(column)
    return unless @releases_sort_column == column

    @releases_sort_direction == 'asc' ? 'sorted-asc' : 'sorted-desc'
  end

  def release_sort_link(label, column, project)
    return label unless RELEASE_SORT_COLUMNS.include?(column)

    next_dir = release_sort_next_direction(column)
    q = request.query_parameters.merge('sort' => column, 'direction' => next_dir)
    q = q.except('page')
    link_to label, project_releases_path(project, q), class: 'rel-sort'
  end

  def release_sort_next_direction(column)
    if @releases_sort_column == column
      @releases_sort_direction == 'asc' ? 'desc' : 'asc'
    else
      default_release_sort_direction_for(column)
    end
  end

  def default_release_sort_direction_for(column)
    %w[created_at start_on release_on progress].include?(column) ? 'desc' : 'asc'
  end
end
