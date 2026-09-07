# frozen_string_literal: true

module SananAgile
  module SprintReport
    # Last N sprints (Versions) ending at the current one, for trend comparison.
    class History
      WINDOW = 5

      Row = Struct.new(
        :version, :current,
        :commit_sp, :commit_be, :commit_fe, :commit_qa,
        :actual_sp, :actual_be, :actual_fe, :actual_qa,
        :completion_pct, :from_snapshot,
        keyword_init: true
      )

      def self.call(version, cfg: nil, limit: WINDOW)
        new(version, cfg: cfg, limit: limit).call
      end

      def initialize(version, cfg: nil, limit: WINDOW)
        @version = version
        @project = version.project
        @cfg = cfg || SananAgile::ProjectSettings.load(@project.id)
        @limit = limit.to_i.positive? ? limit.to_i : WINDOW
      end

      def call
        versions.map do |v|
          report = Calculator.call(v, cfg: @cfg, metrics_only: true)
          Row.new(
            version: v,
            current: v.id == @version.id,
            commit_sp: report.commit_sp,
            commit_be: report.commit_be,
            commit_fe: report.commit_fe,
            commit_qa: report.commit_qa,
            actual_sp: report.actual_sp,
            actual_be: report.actual_be,
            actual_fe: report.actual_fe,
            actual_qa: report.actual_qa,
            completion_pct: completion_pct(report.commit_sp, report.actual_sp),
            from_snapshot: report.from_snapshot
          )
        end
      end

      private

      def versions
        ordered = @project.shared_versions.to_a.sort_by { |v| version_sort_key(v) }
        idx = ordered.index { |v| v.id == @version.id }
        return [@version] if idx.nil?

        from = [idx - (@limit - 1), 0].max
        ordered[from..idx]
      end

      def version_sort_key(v)
        date = v.effective_date || (v.respond_to?(:start_date) && v.start_date) || nil
        [date ? 0 : 1, date || Time.at(0).to_date, v.id]
      end

      def completion_pct(commit, actual)
        c = commit.to_f
        return nil if c <= 0

        ((actual.to_f / c) * 100).round(1)
      end
    end
  end
end
