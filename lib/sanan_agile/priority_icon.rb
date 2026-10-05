# frozen_string_literal: true

module SananAgile
  # Priority icon key (.sanan-agile-priority .priority-<key>) shared by the backlog and the board panel.
  module PriorityIcon
    BY_NAME = {
      'Low' => 'lowest',
      'Normal' => 'default',
      'High' => 'high3',
      'Urgent' => 'high2',
      'Immediate' => 'highest'
    }.freeze

    BY_POSITION = {
      'highest' => 'highest', 'high2' => 'high2', 'high3' => 'high3', 'high' => 'high3', 'high4' => 'high4',
      'high5' => 'high5', 'default' => 'default', 'low3' => 'low3', 'low2' => 'low2', 'lowest' => 'lowest'
    }.freeze

    module_function

    def key(priority)
      return 'default' unless priority

      BY_NAME[priority.name.to_s] ||
        BY_POSITION[priority.respond_to?(:position_name) ? priority.position_name.to_s : ''] ||
        'default'
    end
  end
end
