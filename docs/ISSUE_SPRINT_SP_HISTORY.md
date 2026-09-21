# Plan: Lịch sử SP theo sprint — sanan_redmine_agile

Spec chốt 2026-09-21, chỉnh UX: Size Fibonacci từng team + Total nhập riêng; CF SP ẩn khỏi form gốc.

Liên quan: [BACKLOG_PLAN.md](BACKLOG_PLAN.md), [SPRINT_CLOSE_REPORT_PLAN.md](SPRINT_CLOSE_REPORT_PLAN.md).

---

## 1. Phân biệt Size vs SP sprint

**Hai khối tách nhau. Size = Fibonacci từng team; Total nhập riêng (không cộng). CF SP gốc không hiện trên form.**

```
┌─────────────────────────────────────────────────────────┐
│ Size (ổn định, Fibonacci 0 / 0.5 / 1 / 2 / 3 / 5 / …) │
│   Tổng [ 5 ]   Backend [ 2 ]   Frontend [ 2 ]   QA [ 1 ]│
│   Total ≠ bắt buộc BE+FE+QA                             │
│   Không đổi khi kéo sprint                              │
├─────────────────────────────────────────────────────────┤
│ Sprint này (chỉ hiện khi đã gắn sprint, không phải backlog)│
│   Tổng [fibo]   Backend [fibo]  Frontend [fibo]  QA [fibo] │
│   Total ≠ bắt buộc BE+FE+QA; trống khi vào sprint mới   │
├─────────────────────────────────────────────────────────┤
│ Lịch sử sprint (read-only)                              │
│   Sprint 0  ·  BE 2  FE 2  QA 1                         │
└─────────────────────────────────────────────────────────┘
```

| | **Size** | **SP sprint này** |
|---|---|---|
| Ý nghĩa | Độ lớn ticket (planning) | Effort **sprint đang gắn** |
| Nhập | Tổng + BE/FE/QA, chọn Fibonacci | Tổng + BE/FE/QA, chọn Fibonacci |
| Total | Nhập tay, không cộng team | Nhập tay, không cộng team |
| Đổi sprint | **Giữ nguyên** | Snapshot → history, field **reset trống** |
| Backlog | Đọc Size | Ẩn khối sprint |
| Commit live sprint open | Không | Σ CF team của issue trong sprint |
| Report sprint đã đóng | Không | History `(issue, version)` |

---

## 2. Lưu trữ (tránh 8 CF Redmine)

Hôm nay `story_point_cfid` đang đóng vai **size tổng**; `sp_be_cfid` / `sp_fe_cfid` / `sp_qa_cfid` đang đóng vai **vừa size team vừa commit** — sẽ tách.

| Dữ liệu | Nơi lưu | Ghi chú |
|---|---|---|
| Size tổng | **Giữ** `story_point_cfid` | Ít phá data cũ |
| Size BE / FE / QA | Bảng `sanan_issue_sp_size` | Fibonacci; không reset |
| Sprint tổng / BE / FE / QA | Tổng: `sanan_issue_sprint_sp.sp_total` theo `(issue, version)`; team: CF `sp_be/fe/qa` | Size tổng vẫn là `story_point_cfid` |
| Lịch sử từng sprint | `sanan_issue_sprint_sp` | Unique `(issue_id, version_id)` |

Nếu sau này cần cột/filter Size team trên Issues list → map thêm CF, không đổi UX hai khối.

**Sprint tổng:** nhập tay Fibonacci, không cộng team (giống Size tổng). Lưu `sp_total` trên `sanan_issue_sprint_sp` của version hiện tại.

---

## 3. Quyết định đã chốt

| # | Câu hỏi | Quyết định |
|---|---|---|
| H0 | Size có từng team không? | **Có.** Tổng + BE/FE/QA, Fibonacci. Total nhập riêng, không cộng team. This sprint cũng vậy. |
| H1 | Reset size (tổng + team)? | **Không.** |
| H2 | Reset SP sprint (team CF)? | **Có**, khi đổi `fixed_version_id` sang sprint khác / backlog (không phải reorder). |
| H3 | Snapshot khi nào? | Đổi Version (kéo, bulk move, complete + chuyển issue). |
| H4 | Khóa history? | `(issue_id, version_id)` — kéo lại sprint cũ thì ghi đè. |
| H5 | Backlog → sprint lần đầu | Không snapshot. SP sprint reset trống (size giữ). Số team trên backlog trước đây là CF sprint — coi draft, reset khi vào sprint. |
| H6 | Complete, issue **ở lại** sprint đóng | Không reset SP sprint. |
| H7 | Complete, issue **chuyển** đi | Snapshot sprint cũ + reset SP sprint. |
| H8 | Report | Open: commit live (`fixed_version_id`) **đến cutoff** `commit_lock_days_before_end` (0 = đến Complete). Closed: history + snapshot commit IDs lúc close. Spec: [SPRINT_CLOSE_REPORT_PLAN.md](SPRINT_CLOSE_REPORT_PLAN.md) Q2c–Q2d / §C2–C3. |

---

## 4. Trigger snapshot + reset

```text
old_vid, new_vid = fixed_version_id trước / sau
if old_vid == new_vid: return

if old_vid là sprint thật (không phải Product Backlog bucket):
  upsert history(issue, old_vid, sprint_total, sprint_be, sprint_fe, sprint_qa, user, time)

# vào sprint mới hoặc backlog
clear CF sprint: sp_be_cfid, sp_fe_cfid, sp_qa_cfid
# không copy sprint total sang version mới (row mới trống)
# không đụng story_point_cfid (size tổng)
# không đụng sanan_issue_sp_size (size team)
```

---

## 5. Bảng

**`sanan_issue_sp_size`** — size chuẩn

| Cột | Ý nghĩa |
|---|---|
| `issue_id` | unique |
| `sp_be` / `sp_fe` / `sp_qa` | Size team |

**`sanan_issue_sprint_sp`** — lịch sử SP sprint

| Cột | Ý nghĩa |
|---|---|
| `issue_id`, `version_id` | unique pair |
| `sp_total` | Total nhập tay (không = Σ team) |
| `sp_be` / `sp_fe` / `sp_qa` | CF sprint lúc rời |
| `captured_at`, `captured_by_id` | |

---

## 6. UX / report / code

- Issue show & modal: hai khối + lịch sử.
- Backlog: cột size = `story_point_cfid` (+ size team nếu cần tooltip); không hiện SP sprint trên row trừ khi PO muốn.
- `IssuePatch`: hook đổi Version.
- `Calculator`: commit team open = CF sprint; closed = history.
- Settings: không thêm CF bắt buộc; hiện cột team theo `sp_be/fe/qa_cfid` đã set.

---

## 7. Non-goals

- Một ô dùng chung cho size và sprint
- Reset size
- Snapshot mỗi lần sửa SP trong cùng sprint
- Bắt buộc size tổng = size BE+FE+QA

---

## 8. Phase

- [x] Migration `sanan_issue_sp_size` + `sanan_issue_sprint_sp`
- [x] UI hai khối input + lịch sử
- [x] Hook đổi Version: snapshot CF sprint + reset team CF
- [x] Calculator đọc history khi sprint đóng
- [x] Copy/migrate: giá trị `sp_be/fe/qa` hiện có → **size team** (một lần), rồi CF đó chỉ còn nghĩa sprint

**Acceptance**

1. Sửa size team không đổi khi kéo sprint; SP sprint về trống + có dòng history.
2. Hai khối input trên issue; không dùng chung field.
3. Reorder cùng sprint: không snapshot, không reset.
4. Report sprint cũ đúng sau khi ticket sang sprint mới.
