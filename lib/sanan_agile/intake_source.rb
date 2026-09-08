# frozen_string_literal: true

module SananAgile
  # Resolve / set Intake source for CS·Sale·Product lanes.
  module IntakeSource
    module_function

    def cfid(cfg)
      cfg['intake_source_cfid'].to_i
    end

    def value_for(issue, cfg)
      id = cfid(cfg)
      return nil if id <= 0

      cv = issue.custom_value_for(id)
      normalize(cv&.value)
    end

    def set!(issue, cfg, source)
      id = cfid(cfg)
      return false if id <= 0

      key = normalize(source)
      return false if key.blank?

      issue.safe_attributes = { 'custom_field_values' => { id.to_s => key } }
      true
    end

    def normalize(raw)
      s = raw.to_s.strip.downcase
      return nil if s.blank?

      return 'cs' if %w[cs customer_service customer-service].include?(s)
      return 'sale' if %w[sale sales].include?(s)
      return 'product' if %w[product prod].include?(s)

      s
    end

    def queue_version_id(cfg, lane)
      case lane.to_s
      when 'cs' then cfg['cs_queue_version_id'].to_i
      when 'sale' then cfg['sale_queue_version_id'].to_i
      else 0
      end
    end

    def intake_queue_version_ids(cfg)
      [cfg['cs_queue_version_id'], cfg['sale_queue_version_id']].map(&:to_i).reject(&:zero?).uniq
    end
  end
end
