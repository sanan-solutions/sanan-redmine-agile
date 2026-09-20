# Plan: SLA Engine (CS / Support) — sanan_redmine_agile

## 1. Mục tiêu

Xây **SLA engine** trên Redmine (plugin `sanan_redmine_agile`) để:

- Đo thời gian phản hồi / xử lý ticket theo **policy** (không chỉ “số ngày nằm Ready queue”)
- Cảnh báo trước khi breach, đánh dấu breach, escalate đúng người
- Báo cáo % đạt SLA theo lane (CS / Sale / Product), priority, agent
- Tái dùng backlog CS/Sale + CF `Intake source` đã có — **không** thay Product Backlog / Releases / Agile board

**Không nhầm với SLA nhẹ hiện tại** (đã ship trong CS/Sale Phase 3):

| Đã có (light) | Engine này (full) |
|---|---|
| Age (ngày) trên QUEUE Ready | Đồng hồ **Response / Resolve** theo policy |
| Tô đỏ khi ≥ N ngày Ready | Warning / Breach theo phút–giờ + calendar |
| Banner + mail khi Ready SP vượt ngưỡng | Escalation theo mức, pause/resume, báo cáo compliance |

Tham chiếu: `docs/CS_SALE_BACKLOG_PLAN.md` §12 (out of scope “SLA engine”) → plan này mở rộng thành roadmap riêng.

---

## 2. Bối cảnh & nhu cầu

### 2.1 Ai dùng

| Vai trò | Nhu cầu SLA |
|---|---|
| **CS** | Biết ticket nào sắp/đã quá hạn phản hồi hoặc xử lý |
| **Sale** (optional) | SLA nhẹ hơn hoặc tắt theo lane |
| **Lead / Manager** | Escalation, dashboard % đạt SLA |
| **PO / Product** | Chủ yếu quan tâm Ready-queue age + quota (đã có); SLA resolve thường thuộc CS |

### 2.2 Vòng đời ticket (gắn Intake)

```
Tạo ticket (CS queue)
  → [SLA Response clock START]
  → Lần comment / đổi status đầu từ CS (không phải khách)
  → [SLA Response STOP — met hoặc breach]
  → Làm rõ / Ready / PO pull → Product sprint
  → [SLA Resolve clock — tùy policy: từ create hoặc từ Ready]
  → Status closed / Done
  → [SLA Resolve STOP]
```

Engine phải **tách** rõ:

1. **Response SLA** — thời gian đến lần tương tác đầu (acknowledge)
2. **Resolve SLA** — thời gian đến khi “xong” (closed / status đích)
3. *(Optional)* **Ready-wait SLA** — thời gian nằm Ready chờ PO (đã gần với light SLA hiện có → có thể gộp vào engine như một policy type)

---

## 3. Định nghĩa nghiệp vụ

### 3.1 Thuật ngữ

| Thuật ngữ | Nghĩa |
|---|---|
| **Policy** | Bộ rule: áp dụng khi nào, target bao lâu, calendar nào |
| **Clock** | Đồng hồ đang chạy trên 1 issue cho 1 metric (response / resolve) |
| **Business hours** | Chỉ đếm giờ trong lịch làm việc (VD 9–18, T2–T6) |
| **Pause** | Tạm dừng clock (chờ khách, chờ PO, Pending) |
| **Warning** | Còn X% thời gian hoặc còn N phút → cảnh báo |
| **Breach** | Hết target mà chưa đạt điều kiện stop |
| **Escalation** | Sau breach (hoặc trước): đổi assignee / watcher / mail Lead |

### 3.2 Điều kiện start / stop / pause (đề xuất mặc định)

| Metric | Start | Stop (met) | Pause khi |
|---|---|---|---|
| **Response** | Issue tạo (hoặc vào CS/Sale queue) | Journal đầu tiên bởi member CS/Sale (comment hoặc đổi status), **không** tính author nếu author là khách ngoài | Status ∈ Pending / Waiting customer |
| **Resolve** | Issue tạo (hoặc sau Response met — **chọn 1**, xem §5) | Status ∈ closed **hoặc** status ∈ `resolve_status_ids` | Pending / Waiting customer; *(optional)* Waiting PO Ready |
| **Ready-wait** | Status ∈ Ready **và** còn trên queue Version | Rời Ready **hoặc** PO pull khỏi queue | — |

### 3.3 Target theo priority (ví dụ — chốt khi implement)

| Priority | Response (business hours) | Resolve (business hours) |
|---|---|---|
| Immediate | 1h | 8h |
| Urgent | 2h | 1 ngày |
| High | 4h | 2 ngày |
| Normal | 1 ngày | 5 ngày |
| Low | 2 ngày | 10 ngày |

Có thể override theo **lane** (`cs` / `sale`) hoặc tracker.

### 3.4 Calendar

- Project setting: timezone + weekly schedule + ngày nghỉ
- Fallback: calendar 24/7 (elapsed wall-clock) nếu chưa cấu hình

### 3.5 Customer deadline (CF hẹn khách) — bổ sung vận hành

Ngoài đồng hồ SLA policy, CS thường có **ngày hẹn với khách** (promised date):

| Mục | Chi tiết |
|---|---|
| Setting | `customer_deadline_cfid` — CF Issue kiểu **Date** / DateTime |
| UI | Cột **Deadline hẹn KH** trên CS/Sale backlog (QUEUE + IN PRODUCT); quick-edit; tô đỏ nếu quá hạn và issue chưa closed |
| Quan hệ SLA | **Không thay** Response/Resolve clock. Có thể dùng làm input Phase 3 (cảnh báo nếu deadline KH sớm hơn due_at Resolve) |

Tạo CF trong Redmine Admin → Custom fields → Issues (format Date), gắn tracker CS/Sale, rồi chọn trong Project Settings → Sanan Agile.

---

## 4. Thiết kế kỹ thuật (phác thảo)

### 4.1 Lưu trữ

**Option A — bảng riêng (khuyến nghị)**

```
sanan_agile_sla_policies
  id, project_id, name, lane (cs|sale|all), active, ...

sanan_agile_sla_policy_targets
  policy_id, priority_id (nullable), metric (response|resolve|ready_wait),
  target_minutes, warning_pct (vd 80)

sanan_agile_sla_calendars
  project_id, timezone, weekly_json, holidays_json

sanan_agile_sla_clocks
  issue_id, metric, policy_id,
  started_at, paused_at, accumulated_paused_seconds,
  due_at, warned_at, breached_at, met_at, status (running|paused|met|breached)
```

**Option B — chỉ Custom Field + JSON trên issue**  
Nhanh hơn nhưng khó query/báo cáo → chỉ dùng MVP cực hẹp, không khuyến nghị cho engine.

### 4.2 Tính due_at

```
due_at = add_business_minutes(started_at, target_minutes, calendar)
         + điều chỉnh khi pause/resume
```

Job định kỳ (cron / `rails runner` / Redmine recurring) mỗi 5–15 phút:

1. Scan clocks `running`
2. Nếu `now >= warning_threshold` và chưa `warned_at` → notify
3. Nếu `now >= due_at` và chưa met → `breached`, escalate

Hook realtime (Issue model / Journal after_create):

- Start clock khi tạo / đổi lane
- Pause / resume theo status
- Stop met khi đủ điều kiện

### 4.3 UI

| Chỗ | Hiển thị |
|---|---|
| CS/Sale backlog row | Chip `2h left` / `BREACH` / `Paused` (thay hoặc bổ sung cột Age) |
| Issue detail | Panel SLA: Response / Resolve + timeline |
| Agile board card | Dot màu (green/yellow/red) optional |
| Dashboard / report | % met, avg response, breach count theo tuần |
| Project settings | Policy, calendar, escalation targets |

### 4.4 Notify / escalate

| Sự kiện | Kênh |
|---|---|
| Warning | Mail assignee + watchers; optional Slack/webhook sau |
| Breach | Mail assignee + Lead (role / user ids trong settings) |
| Escalation L2 | Đổi assignee **hoặc** chỉ add watcher Lead (chốt §5) |

Tái dùng pattern mail throttle đã có (`IntakeQueueHealth` / `SananAgileMailer`) — tránh spam.

### 4.5 Liên kết code hiện có

| Thành phần hiện tại | Vai trò với SLA engine |
|---|---|
| `IntakeQueueHealth` + `intake_ready_sla_days` | Phase 0 / migrate thành metric `ready_wait` hoặc giữ song song đến Phase 2 engine |
| CF `Intake source` | Scope policy theo lane |
| CS/Sale Ready statuses | Start/stop Ready-wait; filter candidate PO |
| `SananAgileMailer` | Thêm template warning / breach |

---

## 5. Quyết định cần chốt (open questions)

| # | Câu hỏi | Gợi ý mặc định |
|---|---|---|
| Q1 | Resolve clock start từ **create** hay sau **Response met**? | Sau Response met (tránh double-count lúc chưa ai nhận) |
| Q2 | Đếm **business hours** hay 24/7? | Business hours + calendar project |
| Q3 | Comment của **khách** (non-member) có stop Response không? | Không — chỉ member có permission CS/Sale hoặc `edit_issues` |
| Q4 | PO pull có **pause Resolve** không? | Optional pause “Waiting Product”; mặc định **không** pause |
| Q5 | Breach có **auto đổi status** không? | Không — chỉ flag + notify |
| Q6 | Escalation có **đổi assignee** không? | Phase 1: chỉ mail + watcher; Phase 2: optional reassign |
| Q7 | Sale có cùng policy CS không? | Policy riêng; Sale có thể tắt |
| Q8 | Lưu lịch sử breach khi policy đổi? | Snapshot `target_minutes` trên clock lúc start |
| Q9 | Chatbot / portal khách? | **Ngoài scope** (xem §8) |

---

## 6. Phân phase

### Phase 0 — Giữ & tài liệu hóa SLA nhẹ (đã có)

- [x] Age Ready queue + breach visual
- [x] Threshold Ready SP + banner / mail ngày
- [ ] Đánh dấu rõ trong UI đây là “Ready-wait (simple)”, link tới settings
- [ ] Không phá API hiện tại khi thêm engine

### Phase 1 — SLA MVP (Response + Resolve, 24/7 hoặc calendar đơn giản)

**Scope**

- [ ] Bảng `sla_policies` / `sla_targets` / `sla_clocks`
- [ ] Settings: bật SLA; target theo priority (minutes); warning %
- [ ] Hook: start Response lúc tạo trên CS/Sale queue; stop khi journal member
- [ ] Hook: start Resolve (theo Q1); stop khi closed / resolve statuses
- [ ] Pause theo danh sách status Pending
- [ ] Chip trên CS backlog + panel trên issue show
- [ ] Cron/job: mark warned / breached + mail
- [ ] Locales en/vi

**Acceptance**

1. Ticket Immediate: Response target 60’ (wall-clock MVP) → sau 60’ chưa comment CS = BREACH.
2. Comment CS trước hạn → Response = met; Resolve tiếp tục chạy.
3. Đóng issue trước hạn Resolve → Resolve = met.
4. Status Pending → clock pause; thoát Pending → resume, due_at lùi đúng.
5. Không regress CS/Sale backlog, pull, quota, sprint report.

### Phase 2 — Calendar + escalation + report

- [ ] Business hours calendar + holidays
- [ ] Escalation levels (L1 mail Lead, L2 optional reassign)
- [ ] Report page: % met Response/Resolve theo tuần, theo assignee
- [ ] Gộp Ready-wait vào engine (thay hoặc bọc `IntakeQueueHealth`)
- [ ] Dot trên Agile board (optional filter “breached only”)

### Phase 3 — Nâng cao (optional)

- [ ] Policy theo customer / CF VIP
- [ ] Webhook Slack / Teams
- [ ] Multi-project shared calendar
- [ ] Re-open issue → restart Resolve (policy flag)
- [ ] Audit log thay đổi policy

---

## 7. Settings (phác thảo)

```
sla_enabled: '0'
sla_calendar_id: ''              # hoặc inline JSON
sla_response_enabled: '1'
sla_resolve_enabled: '1'
sla_ready_wait_enabled: '1'      # thay intake_ready_sla_days dần
sla_resolve_start: 'after_response' | 'on_create'
sla_pause_status_ids: [...]
sla_resolve_status_ids: [...]    # ngoài is_closed
sla_warning_pct: 80
sla_escalate_user_ids: [...]
sla_escalate_on_breach: '1'
sla_mail_enabled: '1'
# targets: UI bảng priority × metric → minutes
```

Migrate dần:

- `intake_ready_sla_days` → target Ready-wait (days × business day length) **hoặc** giữ dual-run đến khi Phase 2 ổn.

---

## 8. Out of scope (có chủ đích)

| Mục | Lý do |
|---|---|
| **Portal khách** tự tạo/xem ticket | App ngoài Redmine; SLA engine chỉ chạy trên Issue đã có trong Redmine |
| **Chatbot** FAQ / auto-triage | Kênh chat riêng; có thể *gọi* API tạo issue sau |
| **Omnichannel** (Zalo, email inbound parser) | Thuộc helpdesk intake, không thuộc plugin backlog |
| **Thay Zendesk/Freshdesk toàn phần** | Engine trong Redmine phục vụ team nội bộ đã dùng Redmine |
| **Advanced Roadmaps / portfolio** | Plan khác (`BACKLOG_PLAN` out of scope) |

---

## 9. Rủi ro & mitigation

| Rủi ro | Mitigation |
|---|---|
| Cron trễ → breach muộn | Job 5–15’; optional realtime check khi mở backlog |
| Pause sai (quên Pending) | Whitelist status rõ; journal “SLA paused/resumed” |
| Spam mail | Throttle 1 warning + 1 breach / clock; digest Lead |
| Đổi priority giữa chừng | Giữ target snapshot lúc start; optional “recalc on priority change” flag |
| Performance scan nhiều issue | Index `status, due_at`; chỉ scan `running`/`paused` |
| Lẫn với Ready-queue light SLA | UI label khác; Phase 2 gộp một nguồn sự thật |

---

## 10. Thứ tự triển khai đề xuất

1. Chốt Q1–Q8 (§5)
2. Migration clocks + policy + settings UI skeleton
3. Hook start/stop/pause Response & Resolve (wall-clock)
4. Chip backlog CS + issue panel
5. Job warned/breached + mail
6. Calendar business hours
7. Report + escalation
8. Migrate Ready-wait từ `IntakeQueueHealth`
9. QA: CS Immediate breach, pause Pending, PO pull không phá clock

---

## 11. Thành công đo được

- ≥ 95% ticket CS có Response clock đúng start/stop trong UAT
- Lead nhận đúng 1 mail breach / ticket (không spam)
- Báo cáo tuần: % Response met, % Resolve met, top breach assignees
- Ready-queue light SLA không regress trong Phase 1; Phase 2 thay thế sạch

---

## 12. Liên kết

- CS/Sale backlog & intake: `docs/CS_SALE_BACKLOG_PLAN.md`
- Product backlog: `docs/BACKLOG_PLAN.md`
- Sprint close report: `docs/SPRINT_CLOSE_REPORT_PLAN.md`
- Code light SLA hiện tại: `lib/sanan_agile/intake_queue_health.rb`
