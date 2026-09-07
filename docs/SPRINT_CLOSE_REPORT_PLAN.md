# Plan: Sprint Close Report — sanan_redmine_agile

## 1. Mục tiêu

Khi **đóng sprint** (đóng Redmine Version), hệ thống:

1. Tính và **lưu** các chỉ số SP Commit / SP Actual (tổng + BE/FE/Tester)
2. Sinh **báo cáo sprint** gồm:
   - Thông tin cơ bản sprint
   - Chỉ số SP commit / actual
   - Danh sách ticket đã xong
   - Bảng SP theo thành viên

Báo cáo xem lại được sau khi đóng (không chỉ tính one-shot rồi mất).

---

## 2. Quyết định đã chốt

| # | Câu hỏi | Quyết định |
|---|---|---|
| Q1 | Tester Done In Sprint? | **Done QA In Sprint** → setting `done_qa_cfid` (CF Version trên issue) |
| Q2 | SP Commit có freeze lúc Start? | **Không.** Commit **thay đổi trong sprint** — luôn = Σ SP standard đang `fixed_version_id = sprint` (tính live khi sprint còn open; **ghi snapshot lúc close**) |
| Q3 | SP member? | **Chỉ** Σ `story_point_cfid` trên **subtask closed** trong sprint |

---

## 3. Định nghĩa nghiệp vụ

### 3.1. Phạm vi tracker

| Nhóm | Nguồn cấu hình | Dùng cho |
|---|---|---|
| **Standard** | `standard_tracker` (Bug, Story, Task, …) | SP Commit / Actual (tổng + BE/FE/QA) |
| **Subtask** | `subtask_tracker` | SP theo **member** |

### 3.2. Custom fields Issue

| Ý nghĩa nghiệp vụ | Setting key | Ghi chú |
|---|---|---|
| Story Point (tổng) | `story_point_cfid` | |
| SP Backend | `sp_be_cfid` | |
| SP Frontend | `sp_fe_cfid` | |
| SP Tester/QA | `sp_qa_cfid` | |
| Done In Sprint | `dod_cfid` | Version id |
| Done BE In Sprint | `done_be_cfid` | Version id |
| Done FE In Sprint | `done_fe_cfid` | Version id |
| **Done QA In Sprint** | **`done_qa_cfid` (mới trong settings)** | Version id — *không* dùng nhầm `code_done_cfid` |

> **Lệch hiện tại:** `VersionPatch` cộng BE/FE theo `code_done_cfid`, Tester theo `development_done_cfid`.  
> Sửa thành: Actual BE/FE/QA theo **`done_be_cfid` / `done_fe_cfid` / `done_qa_cfid`**.  
> `code_done_cfid` / `development_done_cfid` giữ cho auto-fill status nếu vẫn dùng trên board.

### 3.3. Công thức

#### A) SP Commit (cam kết — **live, có thể đổi trong sprint**)

Tập issue commit = Standard issues có **`fixed_version_id = sprint`** (tại thời điểm tính).

| Metric | Công thức |
|---|---|
| SP Commit | Σ `story_point_cfid` |
| SP Backend Commit | Σ `sp_be_cfid` |
| SP Frontend Commit | Σ `sp_fe_cfid` |
| SP Tester Commit | Σ `sp_qa_cfid` |

- Sprint **open**: report/API tính live (kéo issue vào/ra sprint → commit đổi).
- Sprint **close**: tính lần cuối + **ghi vào Version CF** `sp_*_commit_version_cfid` để retrospective ổn định.

#### B) SP Actual (thực tế lúc **Close sprint** / khi xem report)

Chỉ Standard issues; “done in sprint này” theo CF:

| Metric | Tập issue | Cộng field |
|---|---|---|
| SP Actual | `dod_cfid = sprint.id` | `story_point_cfid` |
| SP Actual Backend | `done_be_cfid = sprint.id` | `sp_be_cfid` |
| SP Actual Frontend | `done_fe_cfid = sprint.id` | `sp_fe_cfid` |
| SP Actual Tester | `done_qa_cfid = sprint.id` | `sp_qa_cfid` |

Lưu Version CF actual_* khi close (`sp_actual_version_cfid`, …).

#### C) Ticket đã xong

Standard issues trong phạm vi sprint thỏa **ít nhất một**:

- Status closed, **hoặc**
- `dod_cfid = sprint.id`

Phạm vi sprint: `fixed_version_id = sprint` **OR** `dod_cfid = sprint.id`.

#### D) SP theo member

Subtask (`subtask_tracker`) **closed**:

- Trong sprint nếu: `fixed_version_id = sprint` **OR** `parent.fixed_version_id = sprint`
- Group by `assigned_to_id` (nil → **Unassigned**)
- SP = Σ **`story_point_cfid`** only

---

## 4. Bối cảnh code hiện có

`lib/sanan_agile/version_patch.rb` — khi `status → closed`:

- Cộng SP actual → Version CF (sai CF BE/FE/Tester so với rule mới)
- **Chưa có:** commit live/snapshot, UI report, tickets done, member table, `done_qa_cfid`

---

## 5. Thiết kế giải pháp

### 5.1. Sprint = Version

### 5.2. Version CF lưu tổng

| Metric | Setting Version CF |
|---|---|
| SP Commit | `sp_commit_version_cfid` **(mới)** |
| SP BE Commit | `sp_be_commit_version_cfid` **(mới)** |
| SP FE Commit | `sp_fe_commit_version_cfid` **(mới)** |
| SP Tester Commit | `sp_qa_commit_version_cfid` **(mới)** |
| SP Actual | `sp_actual_version_cfid` (đã có) |
| SP BE Actual | `sp_be_actual_version_cfid` (đã có) |
| SP FE Actual | `sp_fe_actual_version_cfid` (đã có) |
| SP Tester Actual | `sp_qa_actual_version_cfid` (đã có) |

### 5.3. Report data

- **Phase 1:** Open sprint → tính live. Closed sprint → ưu tiên đọc Version CF cho 8 chỉ số; tickets/members tính lại từ Issue (hoặc snapshot Phase 3).
- **Phase 3 (optional):** JSON snapshot tickets + members lúc close.

### 5.4. UI

`/projects/:project_id/sprints/:id/report` (alias version id)

```
┌─────────────────────────────────────────────────────┐
│ Sprint Report: Sprint 54                            │
│ closed · dates · …                                  │
├───────────────┬─────────────────────────────────────┤
│ COMMIT (live→ │ ACTUAL                              │
│  snapshot)    │                                     │
│ SP / BE / FE  │ SP / BE / FE / QA                   │
│ / QA          │                                     │
├─────────────────────────────────────────────────────┤
│ Last 5 sprints comparison + charts                  │
│  table · Commit vs Actual · BE/FE/QA · % · members  │
├─────────────────────────────────────────────────────┤
│ Completed tickets                                   │
├─────────────────────────────────────────────────────┤
│ Member SP (subtask closed × story_point)            │
└─────────────────────────────────────────────────────┘
```

---

## 6. Service objects

```
lib/sanan_agile/sprint_report/
  calculator.rb   # commit (live) + actual + completed + members
  closer.rb       # lúc close: calc + ghi Version CF commit_* & actual_*
  history.rb      # so sánh tối đa 5 sprint gần nhất (kết thúc ở sprint hiện tại)
```

Không cần `commit_freezer` lúc Start (commit đổi trong sprint).

`VersionPatch` close → `SprintReport::Closer.call(version)`.

---

## 7. Phân phase

### Phase 1 — Close report

- [x] Thêm setting `done_qa_cfid` (+ UI project settings)
- [x] Thêm 4 Version CF commit_* settings
- [x] Refactor `VersionPatch` / `Closer`: actual theo `dod` / `done_be` / `done_fe` / `done_qa` + `standard_tracker`
- [x] `Calculator`: commit live từ `fixed_version_id`; member từ subtask + `story_point_cfid`
- [x] Trang `sprint_reports#show`
- [x] Link/flash sau đóng version
- [x] Locales + permission `view_sprint_reports` (mọi project member)

**Acceptance**

1. Actual BE/FE/QA đúng Done BE/FE/QA In Sprint + standard tracker.
2. Commit = Σ SP standard đang gắn sprint; đổi khi move issue; lúc close ghi CF.
3. Member SP chỉ từ subtask closed × `story_point_cfid`.
4. Report đủ info + tickets done + bảng member.

### Phase 2 — Backlog Start/Complete

- [ ] Complete sprint từ Backlog → đóng Version + mở report
- [ ] Start sprint chỉ set active (không freeze commit)

### Phase 3 — Snapshot & export

- [ ] JSON snapshot tickets/members lúc close
- [ ] CSV/PDF; % Commit vs Actual

---

## 8. Thuật toán Calculator

```text
standard_ids = cfg['standard_tracker']
subtask_ids  = cfg['subtask_tracker']
sid          = version.id

committed = Issue.where(project_id:, tracker_id: standard_ids, fixed_version_id: sid)

commit_sp     = sum_cf(committed, story_point_cfid)
commit_be     = sum_cf(committed, sp_be_cfid)
commit_fe     = sum_cf(committed, sp_fe_cfid)
commit_qa     = sum_cf(committed, sp_qa_cfid)

actual_sp     = sum_cf(standard where CF(dod_cfid)=sid,     story_point_cfid)
actual_be     = sum_cf(standard where CF(done_be_cfid)=sid, sp_be_cfid)
actual_fe     = sum_cf(standard where CF(done_fe_cfid)=sid, sp_fe_cfid)
actual_qa     = sum_cf(standard where CF(done_qa_cfid)=sid, sp_qa_cfid)

completed = standard where (closed OR CF(dod)=sid)
            AND (fixed_version_id=sid OR CF(dod)=sid)

members = subtask closed
          AND (fixed_version_id=sid OR parent.fixed_version_id=sid)
        → group assigned_to → sum story_point_cfid
```

---

## 9. Files dự kiến

```
app/controllers/sprint_reports_controller.rb
app/views/sprint_reports/show.html.erb
app/helpers/sprint_reports_helper.rb
lib/sanan_agile/sprint_report/calculator.rb
lib/sanan_agile/sprint_report/closer.rb
lib/sanan_agile/version_patch.rb
app/views/sanan_agile/project_settings/_tab.html.erb  # done_qa_cfid + commit_* CF
lib/sanan_agile/project_settings.rb
config/routes.rb
init.rb
config/locales/en.yml, vi.yml
assets/stylesheets/sprint_report.css
docs/SPRINT_CLOSE_REPORT_PLAN.md
```

---

## 10. Quyền

- **`view_sprint_reports`**: mọi **member** của project đều xem được report (không giới hạn manager).
- Map permission vào role Member mặc định / require `:member` giống `view_releases`.

## 11. Open còn lại (nhỏ)

1. `done_qa_cfid` — tạo CF mới hay reuse CF “Done QA In Sprint” đã có trên Redmine (chỉ map id trong settings)?

---

## 12. Liên kết

- `docs/BACKLOG_PLAN.md`
- `lib/sanan_agile/version_patch.rb`
- Project Settings → Sanan Agile
