# frozen_string_literal: true

module SananAgile
  module VersionPatch
    def self.included(base)
      base.class_eval do
        has_one :sanan_agile_version_meta,
                class_name: 'SananAgileVersionMeta',
                dependent: :destroy,
                inverse_of: :version

        before_update :sanan_aggr_points_on_close, if: :sanan_will_close?
      end
    end

    def sanan_sprint_start_date
      sanan_agile_version_meta&.start_date
    end

    def sanan_sprint_start_date=(value)
      meta = sanan_agile_version_meta || build_sanan_agile_version_meta
      meta.start_date = value
      meta
    end

    def sanan_cs_quota_sp
      sanan_agile_version_meta&.cs_quota_sp
    end

    def sanan_cs_quota_sp=(value)
      meta = sanan_agile_version_meta || build_sanan_agile_version_meta
      meta.cs_quota_sp = blank_to_nil_decimal(value)
      meta
    end

    def sanan_sale_quota_sp
      sanan_agile_version_meta&.sale_quota_sp
    end

    def sanan_sale_quota_sp=(value)
      meta = sanan_agile_version_meta || build_sanan_agile_version_meta
      meta.sale_quota_sp = blank_to_nil_decimal(value)
      meta
    end

    def save_sanan_sprint_start_date!
      meta = sanan_agile_version_meta
      return true unless meta
      return true if meta.new_record? && meta.start_date.blank? && meta.cs_quota_sp.nil? && meta.sale_quota_sp.nil?

      meta.version_id = id
      meta.save
    end

    private

    def blank_to_nil_decimal(value)
      s = value.to_s.strip
      return nil if s.blank?

      Float(s.tr(',', '.'))
    rescue ArgumentError, TypeError
      nil
    end

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
