# frozen_string_literal: true
Rails.application.routes.draw do
  # Plugin-wide settings (admin)
  get 'admin/sanan_agile', to: 'sanan_agile/global_settings#edit', as: :sanan_agile_global_settings
  put 'admin/sanan_agile', to: 'sanan_agile/global_settings#update'

  # Inline editing of issue list cells
  get 'sanan_agile/issues/:id/inline/:field', to: 'sanan_agile/inline_issues#show', as: :sanan_inline_issue
  patch 'sanan_agile/issues/:id/inline/:field', to: 'sanan_agile/inline_issues#update'

  resources :projects do
    namespace :sanan_agile do
      # Không cần trang edit riêng vì dùng Project Settings tab; chỉ cần endpoint update
      resource :project_settings, only: [:update], controller: 'project_settings'
    end

    # Release Badges API — ĐÃ bỏ khỏi namespace sanan_agile
    get 'release_badges/unreleased_map',
      to: 'release_badges#unreleased_map',
      as: :release_unreleased_map

    get 'intake_badges/source_map',
      to: 'intake_badges#source_map',
      as: :intake_source_map

    get 'epic_badges/epic_map',
      to: 'epic_badges#epic_map',
      as: :epic_map


    resources :releases, controller: 'releases' do
      collection do
        # get  :new            # modal create (layout: false)
        get  :issues_search  # picker datasource (JSON)
      end
      member do
        post   :attach_issues      # add selected issues into release
        delete :detach_item        # remove one issue
        patch  :reorder            # drag/drop ordering
        patch  :update_issue_status
        patch  :update_code_picked
        patch  :change_state       # unreleased/released/archived
        get    :issue_panel        # right panel (HTML)
        get    :edit          # modal edit
        put  :update        # submit edit
      end
    end

    # Sprint close report (version id)
    get 'sprints/:id/report',
        to: 'sprint_reports#show',
        as: :sprint_report

    # Agile board backlog panel
    get 'agile_board_backlog', to: 'sanan_agile/board_backlog#index', as: :sanan_board_backlog
    post 'agile_board_backlog/pull', to: 'sanan_agile/board_backlog#pull', as: :sanan_board_backlog_pull
    post 'agile_board_backlog/push', to: 'sanan_agile/board_backlog#push', as: :sanan_board_backlog_push

    # Backlog (Sprint = Version)
    get 'backlog', to: 'backlogs#show', as: :backlog
    get 'backlog/sections', to: 'backlogs#sections', as: :backlog_sections
    get 'backlog/issues', to: 'backlogs#issues', as: :backlog_issues
    patch 'backlog/reorder', to: 'backlogs#reorder', as: :backlog_reorder
    post 'backlog/sprints', to: 'backlogs#create_sprint', as: :backlog_create_sprint
    patch 'backlog/sprints/:version_id', to: 'backlogs#update_sprint', as: :backlog_sprint
    delete 'backlog/sprints/:version_id', to: 'backlogs#destroy_sprint'
    post 'backlog/sprints/:version_id/start', to: 'backlogs#start_sprint', as: :backlog_start_sprint
    post 'backlog/sprints/:version_id/complete', to: 'backlogs#complete_sprint', as: :backlog_complete_sprint
    post 'backlog/issues', to: 'backlogs#create_issue', as: :backlog_create_issue
    post 'backlog/epics', to: 'backlogs#create_epic', as: :backlog_create_epic
    post 'backlog/bulk_move', to: 'backlogs#bulk_move', as: :backlog_bulk_move
    post 'backlog/attach_to_release', to: 'backlogs#attach_to_release', as: :backlog_attach_to_release
    post 'backlog/bulk_update_status', to: 'backlogs#bulk_update_status', as: :backlog_bulk_update_status
    post 'backlog/bulk_update_priority', to: 'backlogs#bulk_update_priority', as: :backlog_bulk_update_priority
    post 'backlog/bulk_update_tracker', to: 'backlogs#bulk_update_tracker', as: :backlog_bulk_update_tracker
    post 'backlog/bulk_destroy', to: 'backlogs#bulk_destroy', as: :backlog_bulk_destroy
    post 'backlog/quick_update', to: 'backlogs#quick_update', as: :backlog_quick_update
    post 'backlog/pull_intake', to: 'backlogs#pull_intake', as: :backlog_pull_intake
    patch 'backlog/sprint_quota', to: 'backlogs#update_sprint_quota', as: :backlog_sprint_quota

    # Product roadmap (quarterly Epic plan). Path avoids core /projects/:id/roadmap.
    get 'product_roadmap', to: 'roadmaps#show', as: :product_roadmap
    patch 'product_roadmap/move', to: 'roadmaps#move', as: :product_roadmap_move
    patch 'product_roadmap/health', to: 'roadmaps#update_health', as: :product_roadmap_health
    patch 'product_roadmap/span', to: 'roadmaps#update_span', as: :product_roadmap_span
    get 'product_roadmap/data', to: 'roadmaps#data', as: :product_roadmap_data
    post 'product_roadmap/baseline', to: 'roadmaps#create_baseline', as: :product_roadmap_baseline
    delete 'product_roadmap/baseline', to: 'roadmaps#destroy_baseline'

    # CS / Sale intake backlogs
    get 'cs_backlog', to: 'cs_backlogs#show', as: :cs_backlog
    post 'cs_backlog/issues', to: 'cs_backlogs#create_issue', as: :cs_backlog_create_issue
    post 'cs_backlog/quick_update', to: 'cs_backlogs#quick_update', as: :cs_backlog_quick_update

    get 'sale_backlog', to: 'sale_backlogs#show', as: :sale_backlog
    post 'sale_backlog/issues', to: 'sale_backlogs#create_issue', as: :sale_backlog_create_issue
    post 'sale_backlog/quick_update', to: 'sale_backlogs#quick_update', as: :sale_backlog_quick_update
  end

  # Cross-product roadmap (one row per product).
  get 'product_roadmap', to: 'portfolio_roadmaps#show', as: :portfolio_roadmap
  get 'product_roadmap/data', to: 'portfolio_roadmaps#data', as: :portfolio_roadmap_data

  namespace :sanan_agile do
    post 'set_dod', to: 'dod#set_dod', as: :set_dod
    post :set_part_done, to: 'part_dod#set', as: :set_part_done
  end
end
