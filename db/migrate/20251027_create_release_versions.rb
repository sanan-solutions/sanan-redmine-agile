# db/migrate/20251027_create_release_versions.rb
class CreateReleaseVersions < ActiveRecord::Migration[6.1]
  def change
    create_table :release_versions do |t|
      t.references :project, null: false, index: true
      t.string  :name, null: false
      t.date    :start_on
      t.date    :release_on
      t.text    :description
      t.string  :state, null: false, default: 'unreleased' # unreleased/released/archived
      t.string  :release_notes_url
      t.timestamps
    end

    create_table :release_items do |t|
      t.references :release_version, null: false, index: true
      t.integer :issue_id, null: false, index: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :release_items, [:release_version_id, :issue_id],
              unique: true, name: 'idx_release_items_unique'

    create_table :release_version_drivers do |t|
      t.references :release_version, null: false, index: true
      t.integer :user_id, null: false, index: true
      t.timestamps
    end
    add_index :release_version_drivers, [:release_version_id, :user_id],
              unique: true, name: 'idx_release_version_drivers_unique'
  end
end
