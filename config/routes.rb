# frozen_string_literal: true
Rails.application.routes.draw do
  resources :projects do
    namespace :sanan_agile do
      # Không cần trang edit riêng vì dùng Project Settings tab; chỉ cần endpoint update
      resource :project_settings, only: [:update], controller: 'project_settings'
    end

    # Release Badges API — ĐÃ bỏ khỏi namespace sanan_agile
    get 'release_badges/unreleased_map',
      to: 'release_badges#unreleased_map',
      as: :release_unreleased_map


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
  end

  namespace :sanan_agile do
    post 'set_dod', to: 'dod#set_dod', as: :set_dod
    post :set_part_done, to: 'part_dod#set', as: :set_part_done
  end
end
