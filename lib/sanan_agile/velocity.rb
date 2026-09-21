# frozen_string_literal: true

module SananAgile
  # Average Actual SP of the last N closed sprints (independent Total + BE/FE/QA).
  class Velocity
    DEFAULT_WINDOW = 3
    WINDOWS = [3, 5].freeze

    SprintActual = Struct.new(:version, :sp, :be, :fe, :qa, keyword_init: true)
    Result = Struct.new(:window, :sample_size, :sp, :be, :fe, :qa, :sprints, keyword_init: true)

    def self.call(project, cfg: nil, window: nil)
      new(project, cfg: cfg, window: window).call
    end

    def self.window_from(cfg)
      w = cfg.to_h['velocity_window'].to_i
      WINDOWS.include?(w) ? w : DEFAULT_WINDOW
    end

    def initialize(project, cfg: nil, window: nil)
      @project = project
      @cfg = cfg || SananAgile::ProjectSettings.load(project.id)
      @window = window
    end

    def call
      sprints = closed_sprints.filter_map { |v| actuals_for(v) }
      n = sprints.size
      Result.new(
        window: window,
        sample_size: n,
        sp: average(sprints, :sp),
        be: average(sprints, :be),
        fe: average(sprints, :fe),
        qa: average(sprints, :qa),
        sprints: sprints
      )
    end

    def window
      w = @window.to_i
      return w if self.class::WINDOWS.include?(w)

      self.class.window_from(@cfg)
    end

    private

    def closed_sprints
      excluded = (
        SananAgile::IntakeSource.intake_queue_version_ids(@cfg) +
        SananAgile::ProductBacklog.version_ids(@cfg)
      ).uniq
      versions = @project.shared_versions.where(status: 'closed').to_a
      versions.reject! { |v| excluded.include?(v.id) } if excluded.any?
      versions.sort_by! { |v| sort_key(v) }
      versions.last(window)
    end

    def sort_key(version)
      date = version.effective_date || (version.respond_to?(:start_date) && version.start_date) || nil
      [date ? 0 : 1, date || Date.new(0), version.id]
    end

    def actuals_for(version)
      report = SananAgile::SprintReport::Calculator.call(version, cfg: @cfg, metrics_only: true)
      SprintActual.new(
        version: version,
        sp: report.actual_sp.to_f,
        be: report.actual_be.to_f,
        fe: report.actual_fe.to_f,
        qa: report.actual_qa.to_f
      )
    rescue StandardError => e
      Rails.logger.error "[sanan_agile] Velocity failed for version=#{version.id}: #{e.class}: #{e.message}"
      nil
    end

    def average(sprints, key)
      return nil if sprints.blank?

      round_half(sprints.sum { |s| s.public_send(key).to_f } / sprints.size)
    end

    def round_half(n)
      (n.to_f * 2).round / 2.0
    end
  end
end
