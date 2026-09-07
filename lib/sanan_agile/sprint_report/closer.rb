# frozen_string_literal: true

module SananAgile
  module SprintReport
    class Closer
      def self.call(version)
        new(version).call
      end

      def initialize(version)
        @version = version
        @cfg = SananAgile::ProjectSettings.load(version.project_id)
      end

      def call
        return if @cfg.blank?
        return if @cfg['sanan_agile_enabled'].to_s != '1'

        result = Calculator.call(@version, cfg: @cfg, prefer_snapshot: false)
        assign_totals!(result)
        result
      rescue => e
        Rails.logger.error "[sanan_agile] SprintReport::Closer failed for version=#{@version.id}: #{e.class}: #{e.message}"
        nil
      end

      private

      # Assign Version CF values on the in-memory record so the surrounding
      # Version#save (close) persists them — do not call save here.
      def assign_totals!(result)
        values = {}
        {
          'sp_commit_version_cfid' => result.commit_sp,
          'sp_be_commit_version_cfid' => result.commit_be,
          'sp_fe_commit_version_cfid' => result.commit_fe,
          'sp_qa_commit_version_cfid' => result.commit_qa,
          'sp_actual_version_cfid' => result.actual_sp,
          'sp_be_actual_version_cfid' => result.actual_be,
          'sp_fe_actual_version_cfid' => result.actual_fe,
          'sp_qa_actual_version_cfid' => result.actual_qa
        }.each do |setting_key, amount|
          cfid = @cfg[setting_key].to_i
          next if cfid <= 0

          values[cfid.to_s] = format_number(amount)
        end
        return if values.empty?

        @version.custom_field_values = values
      end

      def format_number(n)
        f = n.to_f
        f == f.to_i ? f.to_i.to_s : f.round(2).to_s
      end
    end
  end
end
