# Plan: Sprint Close Report — sanan_redmine_agile

## 1. Mục tiêu

Khi **đóng sprint** (đóng Redmine Version), hệ thống:

1. Tính và **lưu** các chỉ số SP Commit / SP Actual (tổng + BE/FE/Tester)
2. Sinh **báo cáo sprint** gồm:
   - Thông tin cơ bản sprint + **sprint goal**
   - Chỉ số SP commit / actual
   - **Một bảng ticket**: commit (live), DoD, BE/FE/QA, outcome
   - Bảng SP theo thành viên
   - **Goal met** lúc đóng sprint (SM chọn, không tự suy từ %)

Báo cáo xem lại được sau khi đóng (không chỉ tính one-shot rồi mất).

---

## 2. Quyết định đã chốt

| # | Câu hỏi | Quyết định |
|---|---|---|
| Q1 | Tester Done In Sprint? | **Done QA In Sprint** → setting `done_qa_cfid` (CF Version trên issue) |
| Q2 | SP Commit có freeze lúc Start? | **Không.** Commit **live**: standard + `fixed_version_id = sprint`. Nếu setting `commit_dev_status_ids` (tập A) có giá trị → chỉ ticket **status ∈ A**. Trống = mọi ticket trên version (legacy). Snapshot ID lúc close. |
| Q2b | Ticket chuyển sprint thì SP team? | **Snapshot sprint cũ + reset CF team.** Size (`story_point_cfid`) không reset. Spec: [ISSUE_SPRINT_SP_HISTORY.md](ISSUE_SPRINT_SP_HISTORY.md) |
| Q2c | Danh sách ticket commit freeze lúc Start? | **Không.** Commit **live** sau Start: kéo vào/ra → bảng + SP đổi ngay. Snapshot ID **chỉ lúc close**. |
| Q2d | Deadline hết được sửa commit? | **Có, config.** Setting `commit_lock_days_before_end` (integer ≥ 0). **N = 0** (default): không khóa theo ngày, live đến Complete. **N > 0**: ngày cuối được **thêm/gỡ ticket khỏi sprint** = `effective_date − N`. Từ ngày hôm sau → khóa commit set. Không `effective_date` → không khóa theo ngày. Khóa **tập ticket** (đổi Target version vào/ra sprint này); vẫn sửa status / DoD / SP trên ticket đã commit. Complete sprint vẫn move unfinished. |
| Q3 | SP member? | **Chỉ** Σ `story_point_cfid` trên **subtask closed** trong sprint |
| Q4 | Bảng ticket trên report? | **Một bảng.** Cột: source, **Committed**, **DoD**, BE / FE / QA, status, assignee. Footer cộng SP BE/FE/QA done sprint này. |
| Q5 | Sprint goal / meet goal? | Goal = `Version.description` (đã nhập lúc create/edit sprint). Lúc Complete: SM chọn **Met / Partial / Missed** (+ note tùy chọn) → `sanan_agile_version_metas`. **Không** coi Actual/Commit % là “đạt goal”. Bỏ chọn → `unreviewed`. |

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

Tập issue commit = Standard issues có **`fixed_version_id = sprint`**. Nếu `commit_dev_status_ids` được cấu hình → lọc thêm **`status_id ∈ tập A`** (đang phát triển). Status khác trên cùng board (UAT) không tính commit. Setting trống → như legacy (cả version).

| Metric | Công thức |
|---|---|
| SP Commit | Σ `story_point_cfid` |
| SP Backend Commit | Σ `sp_be_cfid` |
| SP Frontend Commit | Σ `sp_fe_cfid` |
| SP Tester Commit | Σ `sp_qa_cfid` |

- Sprint **open**: report/API tính live (kéo issue vào/ra sprint → **cả SP lẫn danh sách ticket** commit đổi).
- Sprint **close**: tính lần cuối + **ghi** Version CF `sp_*_commit_version_cfid` **và** snapshot issue ID commit (xem §3.4). Không freeze giữa sprint.

#### B) SP Actual (thực tế lúc **Close sprint** / khi xem report)

Chỉ Standard issues; “done in sprint này” theo CF:

| Metric | Tập issue | Cộng field |
|---|---|---|
| SP Actual | `dod_cfid = sprint.id` | `story_point_cfid` |
| SP Actual Backend | `done_be_cfid = sprint.id` | `sp_be_cfid` |
| SP Actual Frontend | `done_fe_cfid = sprint.id` | `sp_fe_cfid` |
| SP Actual Tester | `done_qa_cfid = sprint.id` | `sp_qa_cfid` |

Lưu Version CF actual_* khi close (`sp_actual_version_cfid`, …).

#### C) Bảng ticket (một bảng — không tách “completed” / “code done”)

Hàng = union:

| Nguồn | Điều kiện |
|---|---|
| Committed | standard + `fixed_version_id = sprint` (**live** nếu open; **snapshot ID** nếu closed) |
| DoD | `dod_cfid` = sprint |
| Done team | `done_be` / `done_fe` / `done_qa` = sprint |

Cột cờ:

| Cột | Yes khi |
|---|---|
| **Committed** | ID nằm trong tập commit (§C2) |
| **DoD** | `dod_cfid` = sprint (ticket closed **không** đủ để hiện Yes) |
| Backend / Frontend / QA | CF Done * In Sprint = sprint; ô hiện `Xong · SP` |

**Outcome** (derived, không nhập tay):

| Outcome | Rule |
|---|---|
| Done in sprint | Committed + DoD |
| Closed without DoD | Committed + status closed + không DoD |
| Carried over | Committed + không DoD + đã rời version (sau close) |
| Unplanned | Không committed + có Done BE/FE/QA sprint này |

Footer: Σ SP các ô BE/FE/QA đã xong (không cộng Size DoD vào hàng này).

> Ticket closed nhưng chưa DoD vẫn **No** ở cột DoD — phân biệt “đóng status” vs “DoD In Sprint”.

#### C2) Tập commit ticket — live, khóa gần cuối sprint (config)

Cùng rule Q2 / Q2c với SP commit. **Không freeze lúc Start.** Khóa tập ticket theo Q2d.

```text
N = cfg['commit_lock_days_before_end'].to_i   # default 0
end = version.effective_date

commit_set_locked? =
  version still open
  AND N > 0
  AND end.present?
  AND Date.current > (end - N.days)
  # Ngày cuối được add/remove = end - N (inclusive)
  # N = 0 hoặc thiếu due date → không khóa theo ngày

Sprint OPEN && !locked:
  committed_ids = standard where fixed_version_id = sprint
  (mỗi lần mở report tính lại; add/remove trên backlog/board → bảng đổi)

Sprint OPEN && locked:
  committed_ids vẫn = live fixed_version_id
  (set không đổi vì API/UI từ chối kéo vào/ra)
  Report hiện badge “Commit locked” + cutoff date

Sprint CLOSED:
  committed_ids = snapshot lúc Complete (Closer), ghi version meta
  Fallback nếu chưa có snapshot (sprint đóng trước feature):
    unique( SananIssueSprintSp(version) ∪ still on version ∪ dod/done_* = sprint )
```

Enforce khi `commit_set_locked?` (backlog DnD / bulk move / issue Target version / board đổi version vào **hoặc ra** sprint đang mở đó):

- Chặn, flash/JSON error: không còn đổi commit (còn N ngày trước due, đã hết hạn).
- **Không** chặn: sửa issue khác, DoD/BE/FE/QA, SP trên ticket **đã** trong sprint, Complete sprint.

Project Settings (Sanan Agile → Backlog / Sprint):

| Setting | Default | Ý nghĩa |
|---|---|---|
| `commit_lock_days_before_end` | `0` | Số ngày **trước due** (`effective_date`) mà sau ngày `due − N` không còn thêm/gỡ ticket commit. `0` = tắt. |

#### C3) Sprint goal & goal met

| Dữ liệu | Nơi lưu | Khi nào |
|---|---|---|
| Goal text | `versions.description` | Create/edit sprint (đã có) |
| Goal met | `sanan_agile_version_metas.goal_met` = `met` / `partial` / `missed` / `unreviewed` | Complete sprint |
| Note | `sanan_agile_version_metas.goal_note` (text, optional) | Complete sprint |
| Commit IDs lúc close | `sanan_agile_version_metas.commit_issue_ids` (JSON array int) | Closer, cùng lúc SP totals |

Report:

- Khối **Goal** (wiki description) ngay header — không để chìm dưới KPI.
- Badge Met / Partial / Missed / Unreviewed.
- Số hỗ trợ (committed count, DoD count, carried-over, Commit SP vs Actual SP) — **không** tự gắn “đạt goal”.
- Chart completion % = Actual SP / Commit SP **giữ** cho trend SP; **không** dùng làm verdict goal (Actual = Size DoD, Commit = SP team).

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

- **Phase 1:** Open sprint → tính live. Closed sprint → ưu tiên đọc Version CF cho 8 chỉ số; tickets/members tính lại từ Issue.
- **Phase 4:** Snapshot `commit_issue_ids` + `goal_met` lúc close (thay JSON tickets đầy đủ Phase 3 nếu chưa cần).

### 5.4. UI

`/projects/:project_id/sprints/:id/report` (alias version id)

```
┌─────────────────────────────────────────────────────┐
│ Sprint Report: Sprint 54                            │
│ closed · dates · Goal met: Partial                  │
│ GOAL (description)                                  │
├───────────────┬─────────────────────────────────────┤
│ COMMIT (live→ │ ACTUAL                              │
│  snapshot)    │                                     │
│ SP / BE / FE  │ SP / BE / FE / QA                   │
│ / QA          │                                     │
├─────────────────────────────────────────────────────┤
│ Last 5 sprints comparison + charts                  │
│  table · Commit vs Actual · BE/FE/QA · % · members  │
├─────────────────────────────────────────────────────┤
│ Tickets (1 table)                                   │
│  Committed · DoD · BE · FE · QA · outcome           │
│  footer Σ SP team done                              │
├─────────────────────────────────────────────────────┤
│ Member SP (subtask closed × story_point)            │
└─────────────────────────────────────────────────────┘
```

---

## 6. Service objects

```
lib/sanan_agile/sprint_report/
  calculator.rb   # commit (live) + actual + ticket rows (committed/dod/be/fe/qa) + members
  closer.rb       # lúc close: calc + Version CF + commit_issue_ids (+ goal_met từ complete form)
  history.rb      # so sánh tối đa 5 sprint gần nhất (kết thúc ở sprint hiện tại)
```

Không cần `commit_freezer` lúc Start (commit SP **và** danh sách ticket đổi trong sprint).

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

### Phase 2b — Lịch sử SP theo sprint

Chưa làm. Spec đầy đủ: [ISSUE_SPRINT_SP_HISTORY.md](ISSUE_SPRINT_SP_HISTORY.md).

- [ ] Snapshot team SP khi đổi Version; reset BE/FE/QA; không đụng Story Point tổng
- [ ] Report sprint đã đóng đọc history nếu issue đã chuyển đi

### Phase 3 — Snapshot & export

- [ ] JSON snapshot tickets/members lúc close *(Phase 4 `commit_issue_ids` đủ cho list commit; JSON đầy đủ nếu cần export)*
- [ ] CSV/PDF; % Commit vs Actual

### Phase 4 — Commit list live + sprint goal met

Chốt 2026-09-21: **không freeze lúc Start.** Live đến cutoff Q2d (hoặc đến Complete nếu N = 0). Snapshot ID lúc close.

- [x] Một bảng ticket: DoD + BE/FE/QA + footer SP *(đã có trên report)*
- [x] Cột **Committed** live = `fixed_version_id` khi sprint open
- [x] Setting `commit_lock_days_before_end` + chặn add/remove sau cutoff
- [x] Badge cutoff / locked trên report + backlog
- [x] Khối Goal từ `Version.description` trên header report
- [x] Closer: snapshot `commit_issue_ids` lúc Complete
- [x] Complete sprint: radio Met / Partial / Missed + note → version meta; badge trên report
- [x] Outcome derived (done / carried over / unplanned / closed without DoD)

**Acceptance**

1. Sprint open, trước cutoff: kéo ticket vào/ra → cột Committed và Commit SP đổi ngay; không freeze lúc Start.
2. N > 0 và `Date.current > effective_date − N`: không thêm/gỡ ticket khỏi sprint; SP/DoD trên ticket đã commit vẫn sửa được; Complete vẫn chạy.
3. N = 0 hoặc không due date: không khóa theo ngày.
4. Sprint closed: report vẫn liệt kê ticket đã commit lúc Complete dù unfinished đã move.
5. DoD Yes chỉ khi CF DoD = sprint; closed status không đủ.
6. Goal met chỉ từ lựa chọn SM; không auto từ Actual/Commit %.

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

committed_ids_live = standard where fixed_version_id=sid
committed_ids = version.open? ? committed_ids_live
              : (meta.commit_issue_ids.presence || fallback_union)

ticket_rows = unique(committed_ids ∪ dod ∪ done_be ∪ done_fe ∪ done_qa)
  → Committed / DoD / BE / FE / QA flags + outcome

completed = standard where (closed OR CF(dod)=sid)
            AND (fixed_version_id=sid OR CF(dod)=sid)
            # intake buckets vẫn dùng completed; bảng UI = ticket_rows

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
2. Complete sprint: bắt buộc chọn Met/Partial/Missed hay cho skip → `unreviewed`? **Mặc định cho skip.**

---

## 12. Liên kết

- `docs/BACKLOG_PLAN.md`
- `lib/sanan_agile/version_patch.rb`
- Project Settings → Sanan Agile
