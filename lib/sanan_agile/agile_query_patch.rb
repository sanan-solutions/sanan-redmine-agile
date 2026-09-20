# frozen_string_literal: true

# Helpers for Agile board hidden trackers.
# Cards are filtered in plugins/redmine_agile/.../agile_boards/_board.html.erb
# (query-level prepend is unreliable under Redmine/Zeitwerk reload).
module SananAgile
  module AgileQueryPatch
    module_function

    def hidden_tracker_ids_for(project)
      return [] unless project

      cfg = SananAgile::ProjectSettings.load(project.id)
      return [] unless cfg['sanan_agile_enabled'].to_s == '1'

      Array(cfg['agile_board_hidden_tracker_ids']).map(&:to_i).reject(&:zero?).uniq
    end
  end
end
