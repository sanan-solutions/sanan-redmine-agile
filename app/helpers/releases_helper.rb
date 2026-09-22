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

  def release_team_estimated?(issue, part)
    key = part.to_s == 'fe' ? :sp_fe : :sp_be
    row = (@sp_size_by_issue || {})[issue.id]
    return true if row && !row.public_send(key).nil?

    cfg = @settings || SananAgile::ProjectSettings.load(issue.project_id)
    cfid = cfg[part.to_s == 'fe' ? 'sp_fe_cfid' : 'sp_be_cfid'].to_i
    return false if cfid <= 0

    v = issue.custom_field_value(cfid)
    v.is_a?(Array) ? v.any? { |x| x.to_s.strip != '' } : v.to_s.strip != ''
  end

  def release_code_pick_group(issue, item, can_action)
    chips = %w[be fe].map { |part| release_code_pick_cell(issue, part, item, can_action) }.compact
    return content_tag(:span, '', class: 'wi-empty') if chips.empty?

    content_tag(:div, safe_join(chips), class: 'wi-code-picks')
  end

  def release_code_pick_cell(issue, part, item, can_action)
    estimated = item && release_team_estimated?(issue, part)
    return unless estimated

    on = part.to_s == 'fe' ? item.code_picked_fe? : item.code_picked_be?
    label = part.to_s == 'fe' ? l(:label_release_code_picked_fe) : l(:label_release_code_picked_be)
    title = on ? l(:label_release_code_picked_on, part: label) : l(:label_release_code_picked_off, part: label)
    content_tag(
      :button,
      safe_join([
        content_tag(:span, '', class: 'wi-code-pick__box', 'aria-hidden' => 'true'),
        content_tag(:span, label, class: 'wi-code-pick__lbl')
      ]),
      type: 'button',
      class: "wi-code-pick#{' is-on' if on}",
      disabled: !can_action,
      title: title,
      aria: { pressed: on ? 'true' : 'false', label: title },
      data: {
        part: part,
        issue_id: issue.id,
        title_on: l(:label_release_code_picked_on, part: label),
        title_off: l(:label_release_code_picked_off, part: label)
      }
    )
  end

  def release_item_added_cell(item)
    return content_tag(:span, '', class: 'wi-empty', 'aria-hidden' => 'true') unless item&.added_at

    title_parts = [format_time(item.added_at)]
    title_parts << item.added_by.name if item.added_by
    content_tag(:time, format_date(item.added_at),
                class: 'wi-added-at',
                datetime: item.added_at.iso8601,
                title: title_parts.join(' · '))
  end
end
