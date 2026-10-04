# frozen_string_literal: true

module SananAgile
  module SprintReport
    class Calculator
      Result = Struct.new(
        :commit_sp, :commit_be, :commit_fe, :commit_qa,
        :actual_sp, :actual_be, :actual_fe, :actual_qa,
        :completed_issues, :coded_issues, :members, :participants, :from_snapshot,
        :intake, :commit_locked, :commit_cutoff_on, :goal_met, :goal_note,
        keyword_init: true
      )

      MemberRow = Struct.new(:user, :user_id, :issue_count, :sp, keyword_init: true)
      CodedIssueRow = Struct.new(
        :issue, :committed, :dod, :be_done, :fe_done, :qa_done,
        :sp, :be_sp, :fe_sp, :qa_sp, :outcome,
        keyword_init: true
      )
      IntakeBucket = Struct.new(:source, :count, :sp, keyword_init: true)
      IntakeQuota = Struct.new(:source, :quota, :used, :remaining, :pct_of_commit, keyword_init: true)

      def self.call(version, cfg: nil, prefer_snapshot: nil, metrics_only: false, live_commit: false)
        new(version, cfg: cfg, prefer_snapshot: prefer_snapshot, metrics_only: metrics_only,
                     live_commit: live_commit).call
      end

      # live_commit: use the commit set as it stands now even for a closed version (Closer, at close time,
      # before the commit snapshot is written).
      def initialize(version, cfg: nil, prefer_snapshot: nil, metrics_only: false, live_commit: false)
        @version = version
        @project = version.project
        @cfg = cfg || SananAgile::ProjectSettings.load(@project.id)
        @sid = version.id
        @sid_str = version.id.to_s
        @prefer_snapshot = prefer_snapshot.nil? ? version.status.to_s == 'closed' : prefer_snapshot
        @metrics_only = metrics_only
        @live_commit = live_commit
      end

      def call
        issues = @metrics_only ? [] : completed_issues
        coded = @metrics_only ? [] : coded_issues
        members = @metrics_only ? [] : member_rows
        participants = @metrics_only ? [] : sprint_participants
        intake = build_intake(issues)

        if @prefer_snapshot && (snap = snapshot_totals)
          Result.new(base_result_attrs.merge(
            commit_sp: snap[:commit_sp],
            commit_be: snap[:commit_be],
            commit_fe: snap[:commit_fe],
            commit_qa: snap[:commit_qa],
            actual_sp: snap[:actual_sp],
            actual_be: snap[:actual_be],
            actual_fe: snap[:actual_fe],
            actual_qa: snap[:actual_qa],
            completed_issues: issues,
            coded_issues: coded,
            members: members,
            participants: participants,
            from_snapshot: true,
            intake: intake
          ))
        else
          Result.new(base_result_attrs.merge(
            commit_sp: commit_totals[:sp],
            commit_be: commit_totals[:be],
            commit_fe: commit_totals[:fe],
            commit_qa: commit_totals[:qa],
            actual_sp: actual_totals[:sp],
            actual_be: actual_totals[:be],
            actual_fe: actual_totals[:fe],
            actual_qa: actual_totals[:qa],
            completed_issues: issues,
            coded_issues: coded,
            members: members,
            participants: participants,
            from_snapshot: false,
            intake: intake
          ))
        end
      end

      # Ticket ids committed in this sprint (Closer snapshots them at close).
      def commit_snapshot_ids
        committed_issue_ids
      end

      # Per-assignee SP of closed sub-tasks in this sprint, without the rest of the report.
      def member_breakdown
        member_rows
      end

      def base_result_attrs
        meta = @version.sanan_agile_version_meta
        {
          commit_locked: SananAgile::CommitLock.locked?(@version, @cfg),
          commit_cutoff_on: SananAgile::CommitLock.cutoff_on(@version, @cfg),
          goal_met: meta&.goal_met_key || 'unreviewed',
          goal_note: meta&.goal_note.to_s
        }
      end

      def commit_totals
        @commit_totals ||= if @version.status.to_s == 'closed'
                             closed_sprint_commit_totals
                           else
                             live_sprint_commit_totals
                           end
      end

      def live_sprint_commit_totals(issue_ids = nil)
        ids = issue_ids || committed_issue_ids
        be = sum_cf(ids, cfid('sp_be_cfid'))
        fe = sum_cf(ids, cfid('sp_fe_cfid'))
        qa = sum_cf(ids, cfid('sp_qa_cfid'))
        { sp: be + fe + qa, be: be, fe: fe, qa: qa }
      end

      # Closed sprint: the commit set captured at close (else the set as it stands). Tickets removed during
      # the sprint are no longer commit and are not counted. A ticket moved on at Complete had its sprint
      # SP cleared, so its part SP comes from this sprint's history row; others use their live value.
      def closed_sprint_commit_totals
        snap = @live_commit ? nil : @version.sanan_agile_version_meta&.commit_issue_ids_list
        ids = snap.present? ? snap : committed_issue_ids
        return { sp: 0.0, be: 0.0, fe: 0.0, qa: 0.0 } if ids.empty?
        return live_sprint_commit_totals(ids) unless defined?(SananIssueSprintSp)

        still_here = Issue.where(id: ids, fixed_version_id: @sid).pluck(:id)
        moved = ids - still_here
        hist = SananIssueSprintSp.where(version_id: @sid, issue_id: moved)
        live = still_here.any? ? live_sprint_commit_totals(still_here) : { be: 0.0, fe: 0.0, qa: 0.0 }
        be = hist.sum(:sp_be).to_f + live[:be].to_f
        fe = hist.sum(:sp_fe).to_f + live[:fe].to_f
        qa = hist.sum(:sp_qa).to_f + live[:qa].to_f
        { sp: be + fe + qa, be: be, fe: fe, qa: qa }
      end

      def actual_totals
        @actual_totals ||= {
          sp: sum_cf(issue_ids_by_done_cf('dod_cfid'), cfid('story_point_cfid')),
          be: actual_team_sp('done_be_cfid', 'sp_be_cfid', :sp_be),
          fe: actual_team_sp('done_fe_cfid', 'sp_fe_cfid', :sp_fe),
          qa: actual_team_sp('done_qa_cfid', 'sp_qa_cfid', :sp_qa)
        }
      end

      private

      def build_intake(completed)
        commit_ids = committed_issue_ids
        completed_ids = Array(completed).map(&:id)
        commit_sp = commit_totals[:sp].to_f
        {
          enabled: intake_enabled?,
          commit: bucketize(commit_ids),
          completed: bucketize(completed_ids),
          quotas: intake_quotas(commit_sp)
        }
      end

      def intake_enabled?
        SananAgile::IntakeSource.cfid(@cfg).positive? &&
          (@cfg['cs_backlog_enabled'].to_s == '1' || @cfg['sale_backlog_enabled'].to_s == '1')
      end

      def bucketize(issue_ids)
        empty = {
          'product' => IntakeBucket.new(source: 'product', count: 0, sp: 0.0),
          'cs' => IntakeBucket.new(source: 'cs', count: 0, sp: 0.0),
          'sale' => IntakeBucket.new(source: 'sale', count: 0, sp: 0.0)
        }
        return empty if issue_ids.blank?

        sources = sources_by_issue(issue_ids)
        sp_by = sum_cf_by_issue(issue_ids, cfid('story_point_cfid'))
        issue_ids.each do |iid|
          key = sources[iid] || 'product'
          key = 'product' unless %w[cs sale product].include?(key)
          empty[key].count += 1
          empty[key].sp += sp_by[iid].to_f
        end
        empty
      end

      def sources_by_issue(issue_ids)
        field_id = SananAgile::IntakeSource.cfid(@cfg)
        return {} if field_id <= 0 || issue_ids.blank?

        CustomValue.where(
          customized_type: 'Issue',
          custom_field_id: field_id,
          customized_id: issue_ids
        ).pluck(:customized_id, :value).each_with_object({}) do |(iid, val), h|
          h[iid] = SananAgile::IntakeSource.normalize(val) || 'product'
        end
      end

      def intake_quotas(commit_sp_total)
        meta = @version.sanan_agile_version_meta
        used = bucketize(committed_issue_ids)
        %w[cs sale].map do |lane|
          next unless @cfg["#{lane}_backlog_enabled"].to_s == '1'

          raw = lane == 'sale' ? meta&.sale_quota_sp : meta&.cs_quota_sp
          quota = raw.nil? ? nil : raw.to_f
          u = used[lane].sp
          remaining = quota.nil? ? nil : [quota - u, 0].max
          pct = commit_sp_total.positive? ? ((u / commit_sp_total) * 100.0).round(1) : 0.0
          IntakeQuota.new(
            source: lane,
            quota: quota,
            used: u,
            remaining: remaining,
            pct_of_commit: pct
          )
        end.compact
      end

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
        @committed_issue_ids ||= live_committed_issue_ids
      end

      def resolved_committed_ids
        @resolved_committed_ids ||= begin
          if @version.status.to_s == 'closed' && !@live_commit
            snap = @version.sanan_agile_version_meta&.commit_issue_ids_list
            snap.present? ? snap : fallback_committed_ids
          else
            live_committed_issue_ids
          end
        end
      end

      def live_committed_issue_ids
        SananAgile::SprintCommit.issue_ids(@version, @cfg)
      end

      def fallback_committed_ids
        hist_ids = defined?(SananIssueSprintSp) ? SananIssueSprintSp.where(version_id: @sid).distinct.pluck(:issue_id) : []
        (
          live_committed_issue_ids +
            hist_ids +
            issue_ids_by_done_cf('dod_cfid') +
            issue_ids_by_done_cf('done_be_cfid') +
            issue_ids_by_done_cf('done_fe_cfid') +
            issue_ids_by_done_cf('done_qa_cfid')
        ).uniq
      end

      def issue_ids_by_done_cf(setting_key)
        return [] if standard_ids.blank?

        done_cf = cfid(setting_key)
        return [] if done_cf <= 0

        values = [@sid_str]
        values << @version.name.to_s if @version.name.present?
        Issue.joins(:custom_values)
             .where(project_id: @project.id, tracker_id: standard_ids)
             .where(custom_values: { custom_field_id: done_cf, value: values.uniq })
             .distinct
             .pluck(:id)
      end

      def actual_team_sp(done_key, sp_key, hist_col)
        ids = issue_ids_by_done_cf(done_key)
        issue_team_sp_map(ids, sp_key, hist_col).values.sum
      end

      def issue_team_sp_map(ids, sp_key, hist_col)
        return {} if ids.blank?

        live = sum_cf_by_issue(ids, cfid(sp_key))
        present = cf_present_ids(ids, cfid(sp_key))
        hist = sprint_history_by_issue(ids)
        sizes = issue_size_by_issue(ids)
        ids.each_with_object({}) do |iid, h|
          h[iid] = if present.include?(iid)
                     live[iid].to_f
                   elsif hist[iid]
                     hist[iid].public_send(hist_col).to_f
                   elsif sizes[iid]
                     sizes[iid].public_send(hist_col).to_f
                   else
                     0.0
                   end
        end
      end

      def coded_issues
        be_ids = issue_ids_by_done_cf('done_be_cfid')
        fe_ids = issue_ids_by_done_cf('done_fe_cfid')
        qa_ids = issue_ids_by_done_cf('done_qa_cfid')
        dod_ids = issue_ids_by_done_cf('dod_cfid')
        committed_ids = resolved_committed_ids
        completed = completed_issues
        ids = (completed.map(&:id) + committed_ids + be_ids + fe_ids + qa_ids + dod_ids).uniq
        return [] if ids.blank?

        be_set = be_ids.to_set
        fe_set = fe_ids.to_set
        qa_set = qa_ids.to_set
        dod_set = dod_ids.to_set
        committed_set = committed_ids.to_set
        size_sp = sum_cf_by_issue(ids, cfid('story_point_cfid'))
        be_sp = issue_team_sp_map(be_ids, 'sp_be_cfid', :sp_be)
        fe_sp = issue_team_sp_map(fe_ids, 'sp_fe_cfid', :sp_fe)
        qa_sp = issue_team_sp_map(qa_ids, 'sp_qa_cfid', :sp_qa)
        issues = completed.index_by(&:id)
        missing = ids - issues.keys
        if missing.any?
          Issue.where(id: missing)
               .includes(:tracker, :status, :assigned_to)
               .each { |issue| issues[issue.id] = issue }
        end
        ids.sort.reverse.filter_map do |iid|
          issue = issues[iid]
          next unless issue

          committed = committed_set.include?(iid)
          dod = dod_set.include?(iid)
          CodedIssueRow.new(
            issue: issue,
            committed: committed,
            dod: dod,
            be_done: be_set.include?(iid),
            fe_done: fe_set.include?(iid),
            qa_done: qa_set.include?(iid),
            sp: size_sp[iid].to_f,
            be_sp: be_sp[iid].to_f,
            fe_sp: fe_sp[iid].to_f,
            qa_sp: qa_sp[iid].to_f,
            outcome: ticket_outcome(issue, committed, dod, be_set.include?(iid) || fe_set.include?(iid) || qa_set.include?(iid))
          )
        end
      end

      def ticket_outcome(issue, committed, dod, team_done)
        on_sprint = issue.fixed_version_id.to_i == @sid
        closed = issue.status&.is_closed?
        if committed && dod
          'done'
        elsif committed && !dod && closed
          'closed_without_dod'
        elsif committed && !dod && !on_sprint
          'carried_over'
        elsif !committed && team_done
          'unplanned'
        elsif committed
          'in_sprint'
        else
          'other'
        end
      end

      def cf_present_ids(issue_ids, field_id)
        return [] if field_id.to_i <= 0 || issue_ids.blank?

        CustomValue.where(
          customized_type: 'Issue',
          custom_field_id: field_id,
          customized_id: issue_ids
        ).where("custom_values.value IS NOT NULL AND custom_values.value != ''")
         .distinct.pluck(:customized_id)
      end

      def sprint_history_by_issue(issue_ids)
        return {} unless defined?(SananIssueSprintSp) && issue_ids.present?

        SananIssueSprintSp.where(version_id: @sid, issue_id: issue_ids).index_by(&:issue_id)
      end

      def issue_size_by_issue(issue_ids)
        return {} unless defined?(SananIssueSpSize) && issue_ids.present?

        SananIssueSpSize.where(issue_id: issue_ids).index_by(&:issue_id)
      end

      def completed_issues
        @completed_issues ||= load_completed_issues
      end

      def load_completed_issues
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
