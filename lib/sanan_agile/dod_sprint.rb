# frozen_string_literal: true

module SananAgile
  # Resolve DoD In Sprint (dod_cfid) on issues to a version id + display name.
  module DodSprint
    module_function

    # Tickets offered for DoD when completing a sprint: committed in this sprint, in a DoD status (and
    # tracker), and not already DoD in another sprint (e.g. reached DoD last sprint, only UAT here).
    def complete_candidate_ids(version, cfg)
      cfid = cfg.to_h['dod_cfid'].to_i
      status_ids = Array(cfg['dod_checkbox_statuses']).map(&:to_i).reject(&:zero?)
      return [] if version.nil? || cfid <= 0 || status_ids.empty?

      scope = Issue.where(id: SprintCommit.issue_ids(version, cfg), status_id: status_ids)
      tracker_ids = Array(cfg['dod_checkbox_trackers']).map(&:to_i).reject(&:zero?)
      scope = scope.where(tracker_id: tracker_ids) if tracker_ids.any?
      ids = scope.pluck(:id)
      return [] if ids.empty?

      elsewhere = CustomValue.where(customized_type: 'Issue', custom_field_id: cfid, customized_id: ids)
                             .where.not(value: [nil, '', version.id.to_s, version.name.to_s])
                             .pluck(:customized_id)
      ids - elsewhere
    end

    def issue_map(issues, cfg)
      cfid = cfg && cfg['dod_cfid'].to_i
      return {} if cfid <= 0

      cf = IssueCustomField.find_by(id: cfid)
      version_format = cf && cf.field_format == 'version'

      raw = {}
      Array(issues).each do |issue|
        val = issue.custom_field_value(cfid)
        val = val.is_a?(Array) ? val.find { |x| x.to_s.strip != '' } : val
        next if val.to_s.strip.empty?

        raw[issue.id] = val.to_s.strip
      end
      return {} if raw.empty?

      versions_by_id = {}
      versions_by_name = {}
      if version_format
        ids = raw.values.map(&:to_i).select(&:positive?).uniq
        Version.where(id: ids).each { |v| versions_by_id[v.id.to_s] = v }
      else
        Version.where(name: raw.values.uniq).each { |v| versions_by_name[v.name] = v }
      end

      raw.each_with_object({}) do |(iid, val), h|
        ver = version_format ? versions_by_id[val] : versions_by_name[val]
        h[iid] = {
          'id' => ver ? ver.id.to_s : val,
          'name' => ver ? ver.name : val
        }
      end
    end
  end
end
