# app/controllers/sanan_agile/dod_controller.rb
# frozen_string_literal: true
module SananAgile
  class DodController < ApplicationController
    protect_from_forgery with: :exception
    before_action :require_login
    before_action :find_issue
    before_action :check_permission!

    def set_dod
      cfg  = SananAgile::ProjectSettings.load(@issue.project_id)
      cfid = cfg['dod_cfid'].to_i
      return render json: { ok: false, error: 'CF not configured' }, status: 422 if cfid <= 0

      want_checked = ActiveModel::Type::Boolean.new.cast(params[:checked])

      if want_checked
        # ---- SET: gán Version vào CF ----
        assignable = @issue.assignable_versions
        version = nil
        if (vid = @issue.project.default_version_id)
          version = assignable.find { |v| v.id == vid }
        end
        version ||= assignable.open.reorder(Arel.sql('effective_date IS NULL, effective_date ASC, id DESC')).first
        return render json: { ok: false, error: 'No version found (not assignable)' }, status: 422 unless version

        cf  = IssueCustomField.find_by(id: cfid)
        val = (cf && cf.field_format == 'version') ? version.id.to_s : version.name.to_s

        @issue.init_journal(User.current || User.anonymous, "DoD in Sprint → set CF##{cfid}=#{val}")
        @issue.safe_attributes = { 'custom_field_values' => { cfid.to_s => val } }
        @issue.save(validate: false)

        render json: { ok: true, checked: true, value: version.name,
          href: Rails.application.routes.url_helpers.version_path(version) }
      else
        # ---- CLEAR: xoá giá trị CF ----
        @issue.init_journal(User.current || User.anonymous, "DoD in Sprint → clear CF##{cfid}")
        # đặt về chuỗi rỗng là cách đúng để xoá custom value của Redmine
        @issue.safe_attributes = { 'custom_field_values' => { cfid.to_s => '' } }
        @issue.save(validate: false)

        render json: { ok: true, checked: false }
      end
    end

    private

    def find_issue
      @issue   = Issue.find(params[:issue_id])
      @project = @issue.project
    end

    def check_permission!
      # 1) phải đăng nhập
      return render(json: { ok: false, error: 'not logged in' }, status: 401) unless User.current.logged?
    
      # 2) cần quyền sửa issue trong project
      return render(json: { ok: false, error: 'no permission :edit_issues' }, status: 403) \
        unless User.current.allowed_to?(:edit_issues, @project)
    
      # 3) issue có cho sửa hay không (theo workflow/role)
      editable = @issue.respond_to?(:editable?) ? @issue.editable?(User.current) : true
      return render(json: { ok: false, error: 'issue not editable by current user' }, status: 403) \
        unless editable
    end
    
  end
end
