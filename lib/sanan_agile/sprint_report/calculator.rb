# frozen_string_literal: true

module SananAgile
  module SprintReport
    class Calculator
      Result = Struct.new(
        :commit_sp, :commit_be, :commit_fe, :commit_qa,
        :actual_sp, :actual_be, :actual_fe, :actual_qa,
        :completed_issues, :members, :participants, :from_snapshot,
        keyword_init: true
      )

      MemberRow = Struct.new(:user, :user_id, :issue_count, :sp, keyword_init: true)

      def self.call(version, cfg: nil, prefer_snapshot: nil, metrics_only: false)
        new(version, cfg: cfg, prefer_snapshot: prefer_snapshot, metrics_only: metrics_only).call
      end

      def initialize(version, cfg: nil, prefer_snapshot: nil, metrics_only: false)
        @version = version
        @project = version.project
        @cfg = cfg || SananAgile::ProjectSettings.load(@project.id)
        @sid = version.id
        @sid_str = version.id.to_s
        @prefer_snapshot = prefer_snapshot.nil? ? version.status.to_s == 'closed' : prefer_snapshot
        @metrics_only = metrics_only
      end

      def call
        issues = @metrics_only ? [] : completed_issues
        members = @metrics_only ? [] : member_rows
        participants = @metrics_only ? [] : sprint_participants

        if @prefer_snapshot && (snap = snapshot_totals)
          Result.new(
            commit_sp: snap[:commit_sp],
            commit_be: snap[:commit_be],
            commit_fe: snap[:commit_fe],
            commit_qa: snap[:commit_qa],
            actual_sp: snap[:actual_sp],
            actual_be: snap[:actual_be],
            actual_fe: snap[:actual_fe],
            actual_qa: snap[:actual_qa],
            completed_issues: issues,
            members: members,
            participants: participants,
            from_snapshot: true
          )
        else
          Result.new(
            commit_sp: commit_totals[:sp],
            commit_be: commit_totals[:be],
            commit_fe: commit_totals[:fe],
            commit_qa: commit_totals[:qa],
            actual_sp: actual_totals[:sp],
            actual_be: actual_totals[:be],
            actual_fe: actual_totals[:fe],
            actual_qa: actual_totals[:qa],
            completed_issues: issues,
            members: members,
            participants: participants,
            from_snapshot: false
          )
        end
      end

      def commit_totals
        @commit_totals ||= begin
          ids = committed_issue_ids
          {
            sp: sum_cf(ids, cfid('story_point_cfid')),
            be: sum_cf(ids, cfid('sp_be_cfid')),
            fe: sum_cf(ids, cfid('sp_fe_cfid')),
            qa: sum_cf(ids, cfid('sp_qa_cfid'))
          }
        end
      end

      def actual_totals
        @actual_totals ||= {
          sp: sum_cf(issue_ids_by_done_cf('dod_cfid'), cfid('story_point_cfid')),
          be: sum_cf(issue_ids_by_done_cf('done_be_cfid'), cfid('sp_be_cfid')),
          fe: sum_cf(issue_ids_by_done_cf('done_fe_cfid'), cfid('sp_fe_cfid')),
          qa: sum_cf(issue_ids_by_done_cf('done_qa_cfid'), cfid('sp_qa_cfid'))
        }
      end

      private

      def standard_ids
        @standard_ids ||= Array(@cfg['standard_tracker']).map(&:to_i).reject(&:zero?)
      end

      def subtask_ids
        @subtask_ids ||= Array(@cfg['subtask_tracker']).map(&:to_i).reject(&:zero?)
      end

      def cfid(key)
        @cfg[key].to_i
      end

      def snapshot_totals
        keys = %w[
          sp_commit_version_cfid sp_be_commit_version_cfid
          sp_fe_commit_version_cfid sp_qa_commit_version_cfid
          sp_actual_version_cfid sp_be_actual_version_cfid
          sp_fe_actual_version_cfid sp_qa_actual_version_cfid
        ]
        values = keys.map { |k| read_version_cf(k) }
        return nil if values.all?(&:nil?)

        {
          commit_sp: values[0].to_f,
          commit_be: values[1].to_f,
          commit_fe: values[2].to_f,
          commit_qa: values[3].to_f,
          actual_sp: values[4].to_f,
          actual_be: values[5].to_f,
          actual_fe: values[6].to_f,
          actual_qa: values[7].to_f
        }
      end

      def read_version_cf(setting_key)
        field_id = cfid(setting_key)
        return nil if field_id <= 0

        cv = @version.custom_value_for(field_id)
        return nil if cv.nil? || cv.value.to_s.strip.empty?

        parse_number(cv.value)
      end

      def committed_issue_ids
        return [] if standard_ids.blank?

        Issue.where(project_id: @project.id, tracker_id: standard_ids, fixed_version_id: @sid).pluck(:id)
      end

      def issue_ids_by_done_cf(setting_key)
        return [] if standard_ids.blank?

        done_cf = cfid(setting_key)
        return [] if done_cf <= 0

        Issue.joins(:custom_values)
             .where(project_id: @project.id, tracker_id: standard_ids)
             .where(custom_values: { custom_field_id: done_cf, value: @sid_str })
             .distinct
             .pluck(:id)
      end

      def completed_issues
        return [] if standard_ids.blank?

        closed_ids = IssueStatus.where(is_closed: true).pluck(:id)
        dod_ids = issue_ids_by_done_cf('dod_cfid')

        rel = '(issues.fixed_version_id = :sid'
        rel += ' OR issues.id IN (:dod_ids)' if dod_ids.any?
        rel += ')'

        done = if closed_ids.any? && dod_ids.any?
                 '(issues.status_id IN (:closed) OR issues.id IN (:dod_ids))'
               elsif closed_ids.any?
                 'issues.status_id IN (:closed)'
               elsif dod_ids.any?
                 'issues.id IN (:dod_ids)'
               else
                 return []
               end

        Issue.where(project_id: @project.id, tracker_id: standard_ids)
             .where(rel, sid: @sid, dod_ids: dod_ids)
             .where(done, closed: closed_ids, dod_ids: dod_ids)
             .includes(:tracker, :status, :assigned_to, :priority)
             .order(id: :desc)
             .to_a
      end

      def member_rows
        return [] if subtask_ids.blank?

        closed_ids = IssueStatus.where(is_closed: true).pluck(:id)
        return [] if closed_ids.blank?

        parent_ids = Issue.where(project_id: @project.id, fixed_version_id: @sid).pluck(:id)
        scope = Issue.where(project_id: @project.id, tracker_id: subtask_ids, status_id: closed_ids)
        scope = if parent_ids.any?
                  scope.where('issues.fixed_version_id = ? OR issues.parent_id IN (?)', @sid, parent_ids)
                else
                  scope.where(fixed_version_id: @sid)
                end

        subs = scope.pluck(:id, :assigned_to_id)
        return [] if subs.empty?

        sp_by_issue = sum_cf_by_issue(subs.map(&:first), cfid('story_point_cfid'))
        grouped = Hash.new { |h, k| h[k] = { count: 0, sp: 0.0 } }
        subs.each do |issue_id, user_id|
          grouped[user_id][:count] += 1
          grouped[user_id][:sp] += sp_by_issue[issue_id].to_f
        end

        users = User.where(id: grouped.keys.compact).index_by(&:id)
        grouped.map do |uid, data|
          MemberRow.new(
            user: uid ? users[uid] : nil,
            user_id: uid,
            issue_count: data[:count],
            sp: data[:sp]
          )
        end.sort_by { |r| [r.user ? 0 : 1, r.user&.name.to_s.downcase, -r.sp] }
      end

      # Assignees of issues in this sprint (issue on version, or subtask of parent on version).
      def sprint_participants
        parent_ids = Issue.where(project_id: @project.id, fixed_version_id: @sid).pluck(:id)
        scope = Issue.where(project_id: @project.id).where.not(assigned_to_id: nil)
        scope = if parent_ids.any?
                  scope.where('issues.fixed_version_id = ? OR issues.parent_id IN (?)', @sid, parent_ids)
                else
                  scope.where(fixed_version_id: @sid)
                end

        user_ids = scope.distinct.pluck(:assigned_to_id)
        return [] if user_ids.blank?

        User.where(id: user_ids).sort_by { |u| u.name.to_s.downcase }
      end

      def sum_cf(issue_ids, field_id)
        return 0 if field_id.to_i <= 0 || issue_ids.blank?

        CustomValue.where(
          customized_type: 'Issue',
          custom_field_id: field_id,
          customized_id: issue_ids
        ).pluck(:value).sum { |v| parse_number(v) }
      end

      def sum_cf_by_issue(issue_ids, field_id)
        return {} if field_id.to_i <= 0 || issue_ids.blank?

        CustomValue.where(
          customized_type: 'Issue',
          custom_field_id: field_id,
          customized_id: issue_ids
        ).pluck(:customized_id, :value).each_with_object(Hash.new(0.0)) do |(iid, val), h|
          h[iid] += parse_number(val)
        end
      end

      def parse_number(v)
        return 0.0 if v.nil?

        s = v.to_s.strip.tr(',', '.').gsub(/[_\s]/, '')
        return 0.0 if s.empty?

        Float(s)
      rescue ArgumentError, TypeError
        0.0
      end
    end
  end
end
