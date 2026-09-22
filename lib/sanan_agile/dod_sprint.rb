# frozen_string_literal: true

module SananAgile
  # Resolve DoD In Sprint (dod_cfid) on issues to a version id + display name.
  module DodSprint
    module_function

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
