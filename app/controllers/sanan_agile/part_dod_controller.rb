# frozen_string_literal: true
class SananAgile::PartDodController < ApplicationController
  before_action :find_issue
  before_action :authorize_edit

  # params: issue_id, part: 'be' or 'fe', checked: 'true'/'false'
  def set
    cfg   = SananAgile::ProjectSettings.load(@issue.project_id)
    part  = params[:part].to_s
    check = ActiveModel::Type::Boolean.new.cast(params[:checked])

    cf_done_id =
      case part
      when 'be' then cfg['done_be_cfid'].to_i
      when 'fe' then cfg['done_fe_cfid'].to_i
      else 0
      end

    return render json: { ok: false, error: 'Invalid part or CF not configured' }, status: 422 if cf_done_id <= 0

    version = @issue.project.default_version
    unless version
      # fallback: pick latest open or nearest – bạn đã có VersionPicker thì dùng lại tại đây
      version = @issue.project.shared_versions.open.order('effective_date NULLS FIRST, created_on DESC').first
    end

    if check && version.nil?
      return render json: { ok: false, error: 'No default version' }, status: 422
    end

    # set/clear CF
    @issue.init_journal(User.current, "Sanan Agile: set part=#{part} checked=#{check}")
    set_version_custom_value!(@issue, cf_done_id, version, check)

    # Auto move if both done & config cho phép
    moved = false
    # if cfg['auto_move_enabled'] == '1' && cfg['auto_move_status_id'].present?
    #   if both_parts_done?(@issue, cfg)
    #     moved = move_issue_status!(@issue, cfg['auto_move_status_id'].to_i)
    #   end
    # end

    render json: {
      ok: true,
      checked: check,
      value: (version&.name),
      href: (version ? version_path(version) : nil),
      both_done: both_parts_done?(@issue, cfg),
      auto_moved: moved
    }
  end

  private

  def set_version_custom_value!(issue, cfid, version, checked)
    cf = IssueCustomField.find_by(id: cfid)
    return unless cf

    val =
      if !checked
        nil
      elsif cf.field_format == 'version'
        version.id.to_s
      else
        version.name.to_s
      end

    issue.custom_field_values = { cfid => val }
    issue.save(validate: false)
  end

  def both_parts_done?(issue, cfg)
    fe = value_present?(issue, cfg['done_fe_cfid'])
    be = value_present?(issue, cfg['done_be_cfid'])
    be && fe
  end

  def value_present?(issue, cfid)
    return false if cfid.blank?
    v = issue.custom_field_value(cfid.to_i)
    if v.is_a?(Array) then v.any?(&:present?) else v.present? end
  end

  def move_issue_status!(issue, status_id)
    st = IssueStatus.find_by(id: status_id)
    return false unless st

    # phải đảm bảo workflow cho phép
    return false unless issue.new_statuses_allowed_to(User.current).include?(st)

    issue.init_journal(User.current, 'Sanan Agile: auto move when BE & FE done')
    issue.status_id = st.id
    issue.save(validate: false)
  end

  def find_issue
    @issue = Issue.find(params[:issue_id])
  end

  def authorize_edit
    render_403 unless User.current.allowed_to?(:edit_issues, @issue.project)
  end
end
