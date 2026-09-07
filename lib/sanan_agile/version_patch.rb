# frozen_string_literal: true

module SananAgile
  module VersionPatch
    def self.included(base)
      base.class_eval do
        before_update :sanan_aggr_points_on_close, if: :sanan_will_close?
      end
    end

    private

    def sanan_will_close?
      if respond_to?(:will_save_change_to_status?)
        will_save_change_to_status? && status == 'closed'
      else
        status_changed? && status == 'closed'
      end
    end

    def sanan_aggr_points_on_close
      require_dependency File.expand_path('sprint_report/calculator', __dir__)
      require_dependency File.expand_path('sprint_report/closer', __dir__)
      SananAgile::SprintReport::Closer.call(self)
      true
    end
  end
end

Version.send(:include, SananAgile::VersionPatch) \
  unless Version.included_modules.include?(SananAgile::VersionPatch)
