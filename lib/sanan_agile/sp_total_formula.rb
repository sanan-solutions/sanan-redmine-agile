# frozen_string_literal: true

module SananAgile
  module SpTotalFormula
    FORMULAS = %w[manual max avg].freeze
    FIBO = [0, 0.5, 1, 2, 3, 5, 8, 13, 21, 34].freeze

    module_function

    def formula(cfg)
      v = cfg && cfg['sp_total_formula'].to_s
      FORMULAS.include?(v) ? v : 'manual'
    end

    def require_qa?(cfg)
      cfg && cfg['sp_total_require_qa'].to_s == '1'
    end

    def auto?(cfg)
      formula(cfg) != 'manual'
    end

    def apply_issue!(issue, cfg)
      return unless issue && cfg

      apply_size_total!(issue, cfg)
      apply_sprint_total!(issue, cfg)
    end

    def resolve(be, fe, qa, current = nil, cfg:)
      return nil if require_qa?(cfg) && blank_sp?(qa)

      cur = parse(current)
      return cur unless auto?(cfg) && cur.nil?

      suggested(be, fe, qa, cfg: cfg)
    end

    def suggested(be, fe, qa, cfg:)
      return nil if require_qa?(cfg) && blank_sp?(qa)

      case formula(cfg)
      when 'max'
        max_of(be, fe, qa)
      when 'avg'
        avg_of(be, fe, qa)
      end
    end

    def format_sp(val)
      return '' if val.nil?

      f = val.to_f
      (f % 1).zero? ? f.to_i.to_s : f.to_s
    end

    def apply_size_total!(issue, cfg)
      cfid = cfg['story_point_cfid'].to_i
      return unless cfid.positive?
      return unless auto?(cfg) || require_qa?(cfg)
      return if issue.try(:sanan_sp_size_attrs).nil? && !auto?(cfg)

      h = attrs_hash(issue.try(:sanan_sp_size_attrs))
      if h.empty? && issue.id && defined?(SananIssueSpSize)
        row = SananIssueSpSize.find_by(issue_id: issue.id)
        h = { sp_be: row&.sp_be, sp_fe: row&.sp_fe, sp_qa: row&.sp_qa } if row
      end
      val = resolve(h[:sp_be], h[:sp_fe], h[:sp_qa], issue.custom_field_value(cfid), cfg: cfg)
      issue.custom_field_values = { cfid.to_s => format_sp(val) }
    end

    def apply_sprint_total!(issue, cfg)
      return unless auto?(cfg) || require_qa?(cfg)
      return unless sprint_issue?(issue, cfg)
      return if issue.try(:sanan_sp_sprint_attrs).nil? && !auto?(cfg)

      be = issue.custom_field_value(cfg['sp_be_cfid'].to_i)
      fe = issue.custom_field_value(cfg['sp_fe_cfid'].to_i)
      qa = issue.custom_field_value(cfg['sp_qa_cfid'].to_i)
      h = attrs_hash(issue.try(:sanan_sp_sprint_attrs))
      current = h[:sp_total]
      val = resolve(be, fe, qa, current, cfg: cfg)
      issue.sanan_sp_sprint_attrs = h.merge('sp_total' => format_sp(val))
    end

    def max_of(be, fe, qa)
      nums = [be, fe, qa].map { |v| parse(v) }.compact
      nums.max
    end

    def avg_of(be, fe, qa)
      nums = [be, fe, qa].map { |v| parse(v) }
      return nil if nums.all?(&:nil?)

      mean = nums.map { |n| n || 0.0 }.sum / 3.0
      nearest_fibo(mean)
    end

    def nearest_fibo(n)
      return nil if n.nil?

      FIBO.min_by { |v| [(v.to_f - n.to_f).abs, -v.to_f] }
    end

    def parse(raw)
      return raw if raw.is_a?(Numeric)

      s = raw.to_s.strip.tr(',', '.')
      return nil if s.empty?

      Float(s)
    rescue ArgumentError, TypeError
      nil
    end

    def blank_sp?(raw)
      parse(raw).nil?
    end

    def attrs_hash(raw)
      return {}.with_indifferent_access if raw.nil?

      h = if raw.respond_to?(:to_unsafe_h)
            raw.to_unsafe_h
          elsif raw.respond_to?(:to_h)
            raw.to_h
          else
            {}
          end
      h.with_indifferent_access
    end

    def sprint_issue?(issue, cfg)
      vid = issue.fixed_version_id.to_i
      return false unless vid.positive?
      return false if defined?(SananAgile::ProductBacklog) &&
                      SananAgile::ProductBacklog.version_ids(cfg).include?(vid)

      true
    end
  end
end
