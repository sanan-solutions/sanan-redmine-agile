# Plan: Backlog Management (Jira-like) — sanan_redmine_agile

## 1. Mục tiêu

Thêm màn **Backlog** kiểu Jira để:

- Xếp hạng (rank) issue trong backlog / sprint
- Kéo issue giữa **Backlog** ↔ **Sprint**
- Lên kế hoạch sprint trước khi làm trên Agile board
- Giữ tách biệt với **Releases** (shipping) và **Agile board** (execution)

Luồng mong muốn:

```
Backlog (planning) → gán Sprint (Version)
        ↓
Agile Board (execution) → kéo status trong sprint
        ↓
Releases (shipping) → gắn ReleaseVersion khi gần ship
```

---

## 2. Bối cảnh hiện có

| Khái niệm Jira | Hiện trạng trong stack |
|---|---|
| Board | `redmine_agile` board |
| Sprint | Redmine **Version** (+ CF “From Sprint”) |
| Release | **ReleaseVersion** (đã có trong plugin) |
| Epic | Tracker Epic (project settings) |
| Rank | `agile_data.position` (redmine_agile) |
| Story points | CF / `agile_data.story_points` |

Plugin đã có: Releases, Epic/Standard/Subtask trackers, DoD, release badges, cột/filter Release version trên Issues.

---

## 3. Quyết định thiết kế (cần chốt)

| # | Câu hỏi | Đề xuất mặc định |
|---|---|---|
| D1 | Sprint source of truth? | **Redmine Version** (không tạo entity Sprint mới) |
| D2 | Rank lưu ở đâu? | **`agile_data.position`** |
| D3 | Issue nào vào Backlog? | Tracker thuộc **standard** (+ optional epic/bug qua settings) |
| D4 | Subtask hiện trên Backlog? | **Không** (chỉ parent/standard; giống Jira) |
| D5 | Rank scope? | Rank **theo section** (trong Backlog / trong từng Sprint) — đơn giản hơn rank global |
| D6 | Active sprint xác định thế nào? | Version `open` được đánh dấu active (CF/setting) hoặc “default version” / nearest open |

> Nếu team muốn dùng `agile_sprints` của redmine_agile thay Version → điều chỉnh D1 trước khi code Phase 1.

---

## 4. UX đề xuất

Tab project: **Backlog** (sau Agile, trước hoặc cạnh Releases).

```
┌──────────────────────────────────────────────────────────┐
│ Backlog                    [Create issue] [Create sprint]│
│ Filters: Epic | Tracker | Assignee | Text search        │
├────────────────────────────────────┬─────────────────────┤
│ ACTIVE SPRINT  Sprint name         │ Epic panel          │
│ Goal · dates · Σ SP                │ (filter theo epic)  │
│ ─ ranked issue rows ─              │                     │
│ FUTURE SPRINT(S)                   │                     │
│ ─ ranked issue rows ─              │                     │
│ BACKLOG (unscheduled)              │                     │
│ ─ ranked issue rows ─              │                     │
└────────────────────────────────────┴─────────────────────┘
```

### Hành động chính

- Drag reorder trong một section → cập nhật rank
- Drag giữa Backlog ↔ Sprint → gán / clear `fixed_version_id`
- Click issue → mở detail / global modal (tái sử dụng modal hiện có)
- Create sprint → tạo Version (open)
- Start / Complete sprint (Phase 2)

### Cột / thông tin trên mỗi row

- Key, Type (tracker), Summary, Epic, Priority, Assignee, SP, Status  
- Badge Release version (nếu đã gắn) — optional Phase 1.1

---

## 5. Mô hình dữ liệu

### Tái sử dụng (không migration mới ở MVP)

| Nhu cầu | Nguồn |
|---|---|
| Sprint | `versions` (`fixed_version_id` trên issue) |
| Rank | `agile_data.position` |
| SP | CF story point / `agile_data.story_points` |
| Epic | `issues.parent_id` + `epic_tracker` setting |

### Có thể thêm sau (Phase 2+)

- Project setting: `backlog_trackers`, `backlog_active_version_id`, `backlog_hide_subtasks`
- Optional table `backlog_sprint_meta` (goal, started_on) nếu không muốn nhồi vào Version CF

### Quan hệ với Release

- Không đổi `release_items` / `release_versions`
- Issue có thể vừa thuộc Sprint vừa thuộc Release
- Backlog **không** thay màn Releases

---

## 6. Phân phase

### Phase 1 — MVP (ưu tiên)

**Scope**

- [ ] Menu + quyền `view_backlog`, `manage_backlog`
- [ ] Trang Backlog: sections **Active/Future Sprint(s)** + **Backlog**
- [ ] Load issues theo filter tracker (settings) , loại subtask
- [ ] Drag & drop reorder → API cập nhật `agile_data.position`
- [ ] Drag & drop đổi section → API cập nhật `fixed_version_id` (+ rank)
- [ ] Filter: epic, tracker, assignee, text
- [ ] Hiển thị SP + tổng SP theo section
- [ ] Project settings: bật Backlog, chọn tracker nằm trong backlog

**Non-goals Phase 1**

- Start/Complete sprint workflow
- Epic side panel đầy đủ
- Bulk edit
- Capacity / velocity trên backlog

**API gợi ý**

| Method | Path | Mô tả |
|---|---|---|
| GET | `/projects/:id/backlog` | HTML trang backlog |
| PATCH | `/projects/:id/backlog/reorder` | `{ issue_id, to_version_id\|null, position, before_issue_id? }` |
| GET | `/projects/:id/backlog/issues.json` | datasource filter / refresh partial |

**Files dự kiến (plugin)**

```
app/controllers/backlogs_controller.rb
app/views/backlogs/show.html.erb
app/helpers/backlogs_helper.rb
assets/javascripts/backlog.js
assets/stylesheets/backlog.css
lib/sanan_agile/backlog_query.rb   # scope issues cho backlog
config/routes.rb                  # thêm routes
init.rb                           # menu + permissions
config/locales/en.yml, vi.yml
```

**Acceptance criteria Phase 1**

1. User có quyền thấy tab Backlog khi Sanan Agile bật.
2. Issue chưa có Target version nằm ở section Backlog.
3. Issue có Target version open nằm đúng sprint section.
4. Kéo đổi thứ tự → reload vẫn giữ thứ tự.
5. Kéo vào sprint → `fixed_version_id` đổi; kéo về backlog → clear version.
6. Subtask không xuất hiện trên backlog (theo D4).
7. Không regress Releases / Issue detail Release version / filter Release.

---

### Phase 2 — Sprint lifecycle & UX nâng cao

- [ ] Create sprint (Version) từ UI backlog
- [ ] Sprint goal (Version CF hoặc description convention)
- [ ] Start sprint / Complete sprint
  - Complete: đóng version; option move unfinished → backlog hoặc sprint khác
- [ ] Epic side panel + filter click
- [ ] Quick create issue vào backlog / sprint đang chọn
- [ ] Bulk move selected issues
- [ ] Badge Release version trên row

---

### Phase 3 — Liên kết Releases & báo cáo

- [ ] View “issues in this sprint chưa vào release”
- [ ] Action: add selected → ReleaseVersion (tái sử dụng attach API)
- [ ] Rollup: SP planned / done theo sprint
- [ ] Hook nhẹ với Agile Metrics (nếu cần)

---

## 7. Quyền & settings

### Permissions (`project_module :backlog` hoặc gộp `sanan_agile`)

| Permission | Khả năng |
|---|---|
| `view_backlog` | Xem trang backlog |
| `manage_backlog` | Rank, move sprint, create sprint, quick create |

### Project settings (Phase 1)

- Enable backlog
- Backlog trackers (default = standard_tracker)
- Hide subtasks (default on)
- Active sprint strategy: `default_version` | `manual` | `nearest_open`

---

## 8. Rủi ro & mitigation

| Rủi ro | Mitigation |
|---|---|
| Xung đột rank với agile board | Cùng dùng `agile_data.position`; document rõ; test kéo board + backlog |
| Version vừa là Sprint vừa là milestone khác | Naming convention / filter version status; setting “versions used as sprints” |
| N+1 khi load list lớn | Preload tracker, priority, assigned_to, parent, agile_data, release_item |
| Drag UX nặng | Virtualize sau; Phase 1 limit / “load more” theo section |
| Trùng với redmine_agile backlog (nếu có) | Menu caption “Backlog”; không mount đè controller cũ |

---

## 9. Thứ tự triển khai đề xuất (Phase 1)

1. Routes + permissions + menu stub (empty page)
2. `BacklogQuery` — scope issues + group by version
3. Show view — render sections (no DnD)
4. Reorder API + persist position
5. Move-to-sprint API + persist `fixed_version_id`
6. DnD JS (backlog.js)
7. Filters + SP totals
8. Settings + locales
9. Manual QA checklist (board, releases, issue list filter)

---

## 10. Out of scope (có chủ đích)

- Clone full Jira Advanced Roadmaps / Timeline
- Estimation voting / refinement room
- Cross-project backlog
- Thay thế Agile board hoặc Releases

---

## 11. Open questions (trả lời trước khi code Phase 1)

1. Sprint = **Version** (đề xuất) hay **agile_sprints**?
2. Subtask: **ẩn** (đề xuất) hay hiện dưới parent?
3. Rank: **theo section** (đề xuất) hay global?
4. Có cần Create Sprint ngay trong Phase 1 không, hay chỉ dùng Version có sẵn?

---

## 12. Thành công đo được

- PO/SM xếp được sprint trên Backlog mà không cần Issues list + bulk edit version.
- Thứ tự rank ổn định giữa Backlog và cảm nhận độ ưu tiên trên board.
- Releases vẫn là bước shipping riêng; không bị trộn vào planning.
