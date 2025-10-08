# frozen_string_literal: true
Rails.application.routes.draw do
  resources :projects do
    namespace :sanan_agile do
      # Không cần trang edit riêng vì dùng Project Settings tab; chỉ cần endpoint update
      resource :project_settings, only: [:update], controller: 'project_settings'
      
    end
  end

  namespace :sanan_agile do
    post 'set_dod', to: 'dod#set_dod', as: :set_dod
    post :set_part_done, to: 'part_dod#set', as: :set_part_done
  end
end
