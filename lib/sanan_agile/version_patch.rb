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
      cfg = SananAgile::ProjectSettings.load(project_id)
      return if cfg.blank?

      return if cfg['sanan_agile_enabled'] == '0'

      # --- CF đánh dấu "issue thuộc sprint này" cho từng loại ---
      done_code_in_sprint   = cfg['code_done_cfid'].to_i       # cho SP BE/FE
      done_qa_in_sprint     = cfg['development_done_cfid'].to_i         # cho SP Test
      done_in_sprint_cfid   = cfg['dod_cfid'].to_i            # cho SP tổng

      # --- CF chứa số điểm trên Issue ---
      sp_issue_cfid   = cfg['story_point_cfid'].to_i
      sp_be_issue_cfid= cfg['sp_be_cfid'].to_i
      sp_fe_issue_cfid= cfg['sp_fe_cfid'].to_i
      sp_test_issue_cfid = cfg['sp_qa_cfid'].to_i

      # --- CF đích trên Version (để lưu tổng) ---
      sp_total_version_cfid      = cfg['sp_actual_version_cfid'].to_i
      sp_be_total_version_cfid   = cfg['sp_be_actual_version_cfid'].to_i
      sp_fe_total_version_cfid   = cfg['sp_fe_actual_version_cfid'].to_i
      sp_test_total_version_cfid = cfg['sp_qa_actual_version_cfid'].to_i

      version_value = id.to_s

      # === Tập issue theo từng “done in sprint” tương ứng ===
      issue_ids_for_code = issues_by_cf_value(project_id, done_code_in_sprint, version_value)
      issue_ids_for_qa   = issues_by_cf_value(project_id, done_qa_in_sprint, version_value)
      issue_ids_for_sp   = issues_by_cf_value(project_id, done_in_sprint_cfid, version_value)

      Rails.logger.info "[sanan_agile] v#{id} agg: for_sp=#{issue_ids_for_sp.size} / for_code=#{issue_ids_for_code.size} / for_qa=#{issue_ids_for_qa.size}"

      # === Tính tổng ===
      sp_total      = sum_cf_integer(issue_ids_for_sp,   sp_issue_cfid)
      sp_be_total   = sum_cf_integer(issue_ids_for_code, sp_be_issue_cfid)
      sp_fe_total   = sum_cf_integer(issue_ids_for_code, sp_fe_issue_cfid)
      sp_test_total = sum_cf_integer(issue_ids_for_qa,   sp_test_issue_cfid)


      Rails.logger.info "[sanan_agile] v#{id} totals: SP=#{sp_total}, BE=#{sp_be_total}, FE=#{sp_fe_total}, TEST=#{sp_test_total}"

      # === Ghi về Version (khuyến nghị: dùng CF trên Version) ===
      set_version_cf(sp_total_version_cfid,      sp_total)
      set_version_cf(sp_be_total_version_cfid,   sp_be_total)
      set_version_cf(sp_fe_total_version_cfid,   sp_fe_total)
      set_version_cf(sp_test_total_version_cfid, sp_test_total)

      # Hoặc nếu không tạo CF trên Version, bạn có thể ghi vào description:
      # append_to_description!("Totals on close: SP=#{sp_total}, BE=#{sp_be_total}, FE=#{sp_fe_total}, TEST=#{sp_test_total}")

      true
    end

    # ==== helpers ====
    def issues_by_cf_value(project_id, cfid, value)
      return [] if cfid <= 0
      Issue.joins(:custom_values)
           .where(project_id: project_id)
           .where(custom_values: { custom_field_id: cfid, value: value })
           .distinct
           .pluck(:id)
    end

    def sum_cf_integer(issue_ids, cfid)
      return 0 if cfid <= 0 || issue_ids.empty?
      CustomValue.where(customized_type: 'Issue', custom_field_id: cfid, customized_id: issue_ids)
                 .pluck(:value)
                 .sum { |v| parse_int(v) }
    end

    def parse_int(v)
      return 0 if v.nil?
      s = v.to_s.strip
      return 0 if s.empty?
      s = s.gsub(/[,_\s]/, '') # loại dấu phẩy hoặc cách nếu có
      Integer(s) rescue 0
    end

    def set_version_cf(cfid, value)
      return if cfid.to_i <= 0
      self.custom_field_values = { cfid.to_s => value }
    end
  end
end

Version.send(:include, SananAgile::VersionPatch) \
unless Version.included_modules.include?(SananAgile::VersionPatch)