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

    # Team sizes (BE/FE/QA) and the derived Total apply to standard tickets only. Sub-tasks — and any other
    # non-standard tracker except the Epic tracker — carry only a personal SP (the sprint Total field, used for
    # per-member effort). Without Standard Trackers configured, only Sub-task Trackers are personal.
    def subtask?(issue, cfg)
      return false unless issue && cfg

      tid = issue.tracker_id.to_i
      return true if tracker_ids(cfg, 'subtask_tracker').include?(tid)

      standard = tracker_ids(cfg, 'standard_tracker')
      standard.any? && !standard.include?(tid) && tid != cfg['epic_tracker'].to_i
    end

    def tracker_ids(cfg, key)
      Array(cfg[key]).map(&:to_i).reject(&:zero?)
    end

    # Before an issue is saved (form, inline edit, board, API): derive the Size and Sprint Totals from their
    # BE / FE / QA parts. The Total follows the formula while it is empty or still equal to the formula of the
    # previous parts; a Total typed by hand is kept. With "Require tester SP" the derived Total stays empty
    # until QA is set (a Total typed by hand is still kept).
    def apply_issue!(issue, cfg)
      return unless issue && cfg
      return if subtask?(issue, cfg) # a sub-task only has its personal SP (the sprint Total)
      return unless auto?(cfg) # "Enter Total manually": nothing is derived

      changed = changed_cf_ids(issue)
      %i[size sprint].each { |group| apply_group!(issue, cfg, group, changed) }
    end

    def apply_group!(issue, cfg, group, changed)
      total_id = SananAgile::IssueSp.cfid(cfg, group, :total)
      part_ids = SananAgile::IssueSp.cfids(cfg, group, %i[be fe qa])
      return unless total_id.positive? && part_ids.any?
      return unless issue.new_record? || (changed & (part_ids + [total_id])).any?

      now = SananAgile::IssueSp.values(issue, cfg, group)
      return if changed.include?(total_id) && !now.sp_total.nil? # set by hand in this save: kept
      return if [now.sp_be, now.sp_fe, now.sp_qa].all?(&:nil?) && (changed & part_ids).empty? # nothing to derive from

      before = issue.new_record? ? nil : SananAgile::IssueSp.values_for([issue.id], cfg, group)[issue.id]
      followed = before.nil? || before.sp_total.nil? ||
                 same?(before.sp_total, suggested(before.sp_be, before.sp_fe, before.sp_qa, cfg: cfg))
      return unless now.sp_total.nil? || followed

      # suggested is nil while "Require tester SP" waits for QA: the derived Total stays empty until then.
      set_cf(issue, total_id, suggested(now.sp_be, now.sp_fe, now.sp_qa, cfg: cfg))
    end

    def changed_cf_ids(issue)
      issue.custom_field_values.select { |v| v.value_was.to_s != v.value.to_s }.map(&:custom_field_id)
    end

    def set_cf(issue, cfid, value)
      issue.custom_field_values = { cfid.to_s => format_sp(value) }
    end

    def same?(a, b)
      return a.nil? && b.nil? if a.nil? || b.nil?

      (a.to_f - b.to_f).abs < 0.0001
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

  end
end
