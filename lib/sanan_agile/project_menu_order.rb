# frozen_string_literal: true

module SananAgile
  # Project menu order. Existing menu items are moved, not re-declared, so their url, caption, permission
  # and `if` condition stay as their owner (core, redmine_agile, this plugin) defined them.
  #
  # Result: … Activity | Gantt | Calendar | Roadmap | Product Roadmap | Backlog | CS Backlog | Sale Backlog |
  #         Issues | Agile | Releases | …
  module ProjectMenuOrder
    # Planning items, grouped in this order where the first of them currently sits.
    GROUP = %i[sanan_roadmap backlog cs_backlog sale_backlog issues agile].freeze
    # Then single moves, applied in order: [item, :before|:after, anchor].
    MOVES = [
      [:releases, :after, :agile],
      [:gantt, :before, :roadmap],
      [:calendar, :after, :gantt]
    ].freeze

    module_function

    def apply!
      Redmine::MenuManager.map(:project_menu) do |menu|
        root = menu.menu_items
        group!(root)
        MOVES.each { |name, where, anchor| move!(root, name, where, anchor) }
      end
    end

    def group!(root)
      nodes = GROUP.filter_map { |name| node(root, name) }
      return if nodes.size < 2

      start = nodes.map(&:position).min
      nodes.each { |n| root.remove!(n) }
      nodes.each_with_index { |n, i| root.add_at(n, start + i) }
    end

    def move!(root, name, where, anchor)
      item = node(root, name)
      return unless item && node(root, anchor)

      root.remove!(item)
      target = node(root, anchor).position
      root.add_at(item, where == :before ? target : target + 1)
    end

    def node(root, name)
      root.children.detect { |n| n.name == name }
    end
  end
end
