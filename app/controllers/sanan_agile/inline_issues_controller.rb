# frozen_string_literal: true

# Inline editing of issue list cells (Issues tab): the editor for one cell, and saving it.
class SananAgile::InlineIssuesController < ApplicationController
  helper :queries
  include QueriesHelper
  helper :issues
  helper :custom_fields

  before_action :find_issue
  before_action :check_enabled

  def show
    editor = SananAgile::InlineIssueEdit.editor(@issue, params[:field])
    return render(json: { error: l(:error_sanan_inline_not_editable) }, status: :forbidden) unless editor

    render json: editor.merge(lock_version: @issue.lock_version)
  end

  def update
    field = params[:field].to_s
    value = params[:value].to_s
    unless SananAgile::InlineIssueEdit.editor(@issue, field)
      return render(json: { errors: [l(:error_sanan_inline_not_editable)] }, status: :forbidden)
    end

    @issue.init_journal(User.current)
    @issue.lock_version = params[:lock_version] if params[:lock_version].present?
    @issue.safe_attributes = SananAgile::InlineIssueEdit.attributes_for(@issue, field, value)
    unless SananAgile::InlineIssueEdit.applied?(@issue, field, value)
      return render(json: { errors: [l(:error_sanan_inline_not_allowed)] }, status: :unprocessable_entity)
    end

    if @issue.save
      @issue.reload
      render json: { ok: true, html: cell_html(field), cells: related_cells(field), closed: @issue.closed?,
                     lock_version: @issue.lock_version }
    else
      render json: { errors: @issue.errors.full_messages }, status: :unprocessable_entity
    end
  rescue ActiveRecord::StaleObjectError
    render json: { errors: [l(:notice_issue_update_conflict)], stale: true }, status: :conflict
  end

  private

  def find_issue
    @issue = Issue.visible.find_by(id: params[:id])
    return render(json: { error: l(:error_sanan_board_pull_not_found) }, status: :not_found) unless @issue

    @project = @issue.project
  end

  def check_enabled
    cfg = SananAgile::ProjectSettings.load(@project.id)
    render(json: { error: 'disabled' }, status: :not_found) unless SananAgile::InlineIssueEdit.enabled?(cfg)
  end

  # Other cells of the row a save can change: editing an SP part re-derives its group's Total.
  def related_cells(field)
    cfg = SananAgile::ProjectSettings.load(@project.id)
    sp_fields = SananAgile::IssueSp::KEYS.keys.flat_map { |g| SananAgile::IssueSp.cfids(cfg, g) }.map { |id| "cf_#{id}" }
    return {} unless sp_fields.include?(field)

    (sp_fields - [field]).to_h { |f| [f, cell_html(f)] }
  end

  # The cell as the issue list renders it.
  def cell_html(field)
    column = IssueQuery.new(project: @project).available_columns.detect { |c| c.name.to_s == field }
    column ? view_context.column_content(column, @issue).to_s : ERB::Util.h(@issue.send(field).to_s)
  end
end
