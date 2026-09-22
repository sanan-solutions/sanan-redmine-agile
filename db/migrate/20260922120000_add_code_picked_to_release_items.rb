# frozen_string_literal: true

class AddCodePickedToReleaseItems < ActiveRecord::Migration[6.1]
  def change
    add_column :release_items, :code_picked_be, :boolean, null: false, default: false
    add_column :release_items, :code_picked_fe, :boolean, null: false, default: false
  end
end
