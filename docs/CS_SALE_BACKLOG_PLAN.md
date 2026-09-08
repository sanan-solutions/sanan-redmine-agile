# Plan: Backlog CS & Sale → Product Sprint Intake

## 1. Mục tiêu

Bổ sung luồng backlog riêng cho **Team CS** và **Team Sale**, để:

- CS / Sale tiếp nhận issue (khách hàng / cơ hội bán), đánh giá và gắn **priority**
- Mỗi sprint (hoặc khi xếp Product backlog), **PO** chọn ticket từ backlog CS / Sale theo **độ ưu tiên**, trong giới hạn **quota SP** đã dành cho từng nguồn
- CS / Sale **không** tự đẩy issue vào sprint/backlog Product
- Giữ tách biệt với Product Backlog hiện có (planning nội bộ), Agile board (execution) và Releases (shipping)

Luồng mong muốn:

```
CS nhận issue → gắn Version "CS Backlog" (+ priority, SP)
Sale nhận issue → gắn Version "Sale Backlog" (+ priority, SP)
        ↓
PO đặt quota SP_CS / SP_Sale trên Product sprint (nếu vào sprint)
        ↓  PO chọn ticket theo priority (trong hạn mức SP)
Issue vào Product Sprint Version  và/hoặc  Product Backlog (unscheduled)
        ↓
Agile Board → Releases
```

**Ai làm intake:** chỉ **PO** (Product Owner) — chọn từ 2 nguồn CS & Sale vào sprint hoặc backlog của team Product.

---

## 2. Bối cảnh & nhu cầu nghiệp vụ

### 2.1 Team CS

| Bước | Ai làm | Việc |
|---|---|---|
| 1 | CS | Nhận issue từ khách hàng |
| 2 | CS | Đánh giá, làm rõ, gắn **priority** (+ SP nếu có) |
| 3 | CS | Issue nằm trong **Version CS Backlog** (queue, chưa vào Product sprint) |
| 4 | **PO** | Mỗi Product sprint đặt **quota SP** cho CS (và Sale) |
| 5 | **PO** | Chọn ticket từ CS Backlog → đưa vào **Product sprint** hoặc **Product backlog**, theo priority đến hết quota SP |

### 2.2 Team Sale

Tương tự CS: nhận → đánh giá → priority + SP → **Version Sale Backlog** → **PO** chọn vào Product sprint/backlog trong **quota SP Sale**.

### 2.3 Liên hệ với Product Backlog hiện tại

| Backlog | Chủ | Cơ chế |
|---|---|---|
| Product Backlog | **PO** / Product | Issue team Product; sprint = Product Version |
| CS Backlog | CS (PO xem & chọn) | Issue thuộc Version **CS Backlog** |
| Sale Backlog | Sale (PO xem & chọn) | Issue thuộc Version **Sale Backlog** |

Cùng một project. **PO** là người duy nhất (theo quyền) chọn ticket từ CS/Sale vào sprint hoặc backlog Product; mỗi Product sprint có **quota SP** cho CS và Sale.

---

## 3. Quyết định thiết kế (đã chốt)

| # | Câu hỏi | Quyết định | Ghi chú |
|---|---|---|---|
| S1 | CS/Sale cùng project với Product? | **Cùng 1 Redmine project** | Không tách project |
| S2 | Phân biệt nguồn / hàng đợi CS·Sale? | **Mỗi team một Version riêng** làm “queue backlog” | VD: Version `CS Backlog`, `Sale Backlog` (status open, không dùng làm Product sprint) |
| S3 | Ai chọn ticket CS/Sale vào Product? | **PO** pull: đổi `fixed_version_id` từ Version CS/Sale → Product sprint **hoặc** clear vào Product backlog (unscheduled) | CS/Sale không tự gắn vào sprint/backlog Product |
| S3b | Đích của PO khi chọn? | **Product sprint** và/hoặc **Product backlog** | **Quota SP chỉ trừ khi vào sprint**; vào backlog Product thì **không trừ** (đã chốt) |
| S9 | PO candidate list? | **Chỉ Ready** | Settings: `cs_ready_status_ids`, `sale_ready_status_ids` |
| S10 | Hotfix bypass quota? | **Không** | Vẫn cần SP + trong quota |
| S11 | Unfinished khi complete sprint? | Về **Product backlog** | Không trả queue CS/Sale |
| S12 | Menu & cách ly? | **3 menu riêng**; CS/Sale không thấy phần Product | Permission / menu visibility |
| S13 | CS/Sale trên IN PRODUCT? | **Chỉ comment** (+ xem) | |
| S14 | Watchers khi PO pull? | **Auto-add (mặc định bật)** author/assignee CS·Sale | Đã chốt |
| S15 | Issue mới CS/Sale? | **Auto** gắn Version queue + CF `Intake source` | Đã chốt |
| S4 | Thứ tự chọn? | Theo **Priority** (Immediate → Low), tie-break: position, rồi `id` | Khớp sort backlog hiện tại |
| S5 | Đơn vị quota / effort? | **Story points (SP)** | Quota CS/Sale trên từng Product sprint = số SP tối đa |
| S6 | Ai được edit priority CS/Sale? | CS trên lane CS; Sale trên lane Sale; **PO** có thể override nếu cần | Permission theo lane |
| S7 | Subtask trên CS/Sale backlog? | **Không** | Đồng bộ Product backlog |
| S8 | Đổi nguồn (CS↔Sale↔Product)? | Hiếm; đổi Version queue + journal | Ví dụ CS → Product nếu thành feature |

### Thuật ngữ nhanh

| Viết tắt | Nghĩa |
|---|---|
| **CF** | **Custom Field** — trường tùy chỉnh trên Issue trong Redmine (số, list, text…). Plugin đang dùng CF cho story points / From Sprint, v.v. |
| **SP** | Story points — đơn vị estimate; **quota cũng tính bằng SP** |
| **Version** | Redmine Target version — trong plugin đang dùng như Sprint / hàng đợi |

### Mô hình Version trong cùng project

```
Project X
├── Version "CS Backlog"     ← hàng đợi CS (chưa vào sprint Product)
├── Version "Sale Backlog"   ← hàng đợi Sale
├── Version "Sprint 24"      ← Product sprint (có cs_quota_sp, sale_quota_sp)
└── Version "Sprint 25"      ← Product sprint tương lai
```

- Issue mới trên CS/Sale Backlog: **auto** `fixed_version = queue` + CF `Intake source`
- **PO** pull vào sprint: `fixed_version_id = Sprint 24`, **trừ quota SP** nguồn tương ứng
- **PO** kéo vào Product backlog: clear queue Version → unscheduled Product; CF nguồn giữ; **không trừ quota sprint**
- Role CS/Sale: menu chỉ CS hoặc Sale backlog (+ Issues nếu cần); **không** hiện Product Backlog / phần Product khác

Settings cần lưu:

- `cs_queue_version_id` — Version dùng làm CS Backlog
- `sale_queue_version_id` — Version dùng làm Sale Backlog
- Danh sách / heuristic Version nào là **Product sprint** (ví dụ: không phải queue CS/Sale; hoặc naming / flag trên `sanan_agile_version_metas`)

> **CF `Intake source`:** dùng để nhớ nguồn sau khi PO pull (section IN PRODUCT + quota/report). Version queue vẫn là hàng đợi chính trước khi PO lấy.

---

## 4. UX đề xuất

### 4.1 Entry points

- Menu project:
  - **Backlog** (Product — giữ như hiện tại)
  - **CS Backlog**
  - **Sale Backlog**
- Hoặc một trang **Intake Backlogs** với tab: `Product | CS | Sale`

Khuyến nghị Phase 1: **3 trang/route riêng** (dễ quyền + ít đụng UX Product).

### 4.2 Màn CS Backlog / Sale Backlog (CS/Sale + theo dõi sau khi PO lấy)

```
┌─────────────────────────────────────────────────────────────┐
│ CS Backlog                         [New issue] [Filters]   │
│ Σ queue SP · Σ in-product SP · count                        │
├─────────────────────────────────────────────────────────────┤
│ QUEUE — chờ PO (Version CS Backlog) — sort priority        │
│ ─ issue rows: priority, SP, status CS ─                     │
│                                                             │
│ IN PRODUCT — PO đã lấy (đang làm / chờ sprint)              │
│ ─ sprint|backlog, status Product, % done, assignee ─        │
│                                                             │
│ DONE (gần đây) — closed, nguồn CS (optional)                │
└─────────────────────────────────────────────────────────────┘
```

Hành động CS/Sale:

- **QUEUE**: tạo/sửa, priority, SP, status đánh giá; không tự gắn Product sprint
- **IN PRODUCT**: xem tiến độ (status, sprint, assignee); hạn chế sửa field Product; **comment** OK
- Click issue → modal / issue show (cùng project + `view_issues`)

### 4.5 Theo dõi ticket sau khi PO lấy — các cách làm

Nhu cầu: CS/Sale vẫn **thấy** ticket đã vào Product sprint/backlog và **theo dõi tiến độ**.

Cùng project ⇒ `view_issues` đủ để mở ticket; cần **UI + cách nhớ nguồn** sau khi đổi Version.

| Cách | Ý tưởng | Ưu | Nhược |
|---|---|---|---|
| **A. CF `Intake source` + section IN PRODUCT** | PO pull: giữ CF=`cs`/`sale`, chỉ đổi Version. CS backlog = QUEUE ∪ IN PRODUCT | Đơn giản, filter/report/badge dễ | Cần 1 CF |
| **B. Bảng `intake_pulls`** | Lưu lịch sử pull | Audit chặt | Thêm bảng |
| **C. Không đổi Version** | Sprint Product ở field khác | CS luôn theo Version queue | Lệch Sprint=Version hiện tại |
| **D. Saved Query Redmine** | Query CF=cs & open | Ít code | UX rời |

**Khuyến nghị đã chốt: Cách A** + watcher auto-add

1. CF list **`Intake source`** = `product` | `cs` | `sale` — set khi vào queue, **giữ sau PO pull**
2. CS Backlog sections: **QUEUE** (Version CS) · **IN PRODUCT** (CF=cs và đã rời queue) · optional **DONE**
3. Cột IN PRODUCT: sprint/backlog, status, assignee, done %, SP
4. CS full-edit chỉ khi QUEUE; IN PRODUCT = read-mostly + comment
5. **Mặc định bật:** PO pull → auto-add author/assignee CS·Sale vào **watchers** (mail khi status đổi)

```
#120 trên CS QUEUE → PO chọn vào Sprint 24
     → vẫn hiện CS Backlog / IN PRODUCT
     → Status: In Progress · Assignee: Dev A
     → CS theo dõi đến Done
```

Sale tương tự (`Intake source = sale`).

### 4.3 Intake — PO chọn vào Product Sprint / Backlog

Panel dành cho **PO** trên Product Backlog (hoặc từ CS/Sale backlog với quyền PO):

```
┌─ PO: Pull from CS / Sale ──────────────────────────────────┐
│ Đích: (•) Sprint X   ( ) Product backlog (unscheduled)     │
│ Capacity sprint: 40 SP                                      │
│ Quota CS: 10 SP (đã lấy 6 · còn 4)                          │
│ Quota Sale: 8 SP (đã lấy 2 · còn 6)                         │
│                                                             │
│ [CS candidates — by priority]     [Sale candidates]         │
│ ☐ #120 Immediate  3SP                                       │
│ ☐ #118 High       2SP                                       │
│ ...                                                         │
│ [Add selected]                                              │
└─────────────────────────────────────────────────────────────┘
```

Rule UX:

- Chỉ **PO** (quyền `pull_intake_to_sprint` / `manage_backlog`) mới thấy action chọn
- Đích = sprint → validate `Σ SP ≤ remaining quota` (+ optional capacity sprint); **có trừ quota**
- Đích = Product backlog → rời Version CS/Sale, unscheduled Product; CF nguồn giữ; **không trừ quota**
- PO chỉ thấy candidate **Ready**
- Sort candidates: priority → position → id
- Sau chọn: journal + giữ CF + **auto-add watchers** (author/assignee nguồn)

### 4.4 Hiển thị trên Product Backlog / Board

- Badge nguồn: `CS` / `Sale` / (không badge = Product)
- Filter: `Source = CS|Sale|Product`
- Section sprint: hiện `CS used/quota`, `Sale used/quota`

---

## 5. Mô hình dữ liệu

### 5.1 Tái sử dụng

| Nhu cầu | Nguồn |
|---|---|
| Issue | `issues` |
| Priority | `enumerations` (IssuePriority) |
| Sprint | `versions` / `fixed_version_id` |
| SP | CF story point / `agile_data.story_points` |
| Rank phụ | `agile_data.position` (trong lane unscheduled) |

### 5.2 Cần thêm

#### A. Project settings (`SananAgile::ProjectSettings`)

```yaml
cs_backlog_enabled: '1'
sale_backlog_enabled: '1'
cs_queue_version_id: <Version id>          # Version "CS Backlog"
sale_queue_version_id: <Version id>        # Version "Sale Backlog"
cs_ready_status_ids: [..]                  # optional: status sẵn sàng pull
sale_ready_status_ids: [..]
default_cs_quota_sp: 10                    # gợi ý khi tạo Product sprint
default_sale_quota_sp: 8
allow_quota_override: '0'
```

Nguồn issue được suy ra từ Version:

- `fixed_version_id == cs_queue_version_id` → CS queue
- `fixed_version_id == sale_queue_version_id` → Sale queue
- Version Product / unscheduled: nhận diện nguồn bằng CF `Intake source` (bắt buộc cho theo dõi — §4.5)

#### B. Sprint quota meta (mở rộng `sanan_agile_version_metas`)

| Cột | Ý nghĩa |
|---|---|
| `cs_quota_sp` | **SP** tối đa dành cho issue từ CS trong Product sprint này |
| `sale_quota_sp` | **SP** tối đa dành cho issue từ Sale |
| `sprint_start_date` | (đã có) |
| `is_product_sprint` | optional flag phân biệt Product sprint vs queue CS/Sale |

Tính **đã dùng (SP)**:

```
used_cs_sp   = Σ SP(issue in Product sprint được đánh dấu nguồn CS)
used_sale_sp = Σ SP(issue in Product sprint nguồn Sale)
remaining_cs = cs_quota_sp - used_cs_sp
```

Cách nhớ “issue đã vào Product nhưng gốc CS” (cần cho theo dõi + quota):

- **Khuyến nghị (đã chọn hướng):** CF **`Intake source`** = `cs` | `sale` | `product` — set khi vào queue, **giữ sau khi PO pull**
- Journal khi PO pull: `[backlog intake by PO] from cs → sprint 24`
- Optional sau: bảng `intake_pulls` nếu cần audit

#### C. CF `Intake source` — Phase 1.5 / đầu Phase 2 (không còn “optional mơ hồ”)

Bắt buộc nếu CS/Sale cần theo dõi ticket sau intake (xem §4.5).  
Phase 1 stub có thể tạm list theo Version queue; trước khi ship pull cho PO phải có CF (hoặc tương đương) để section **IN PRODUCT** hoạt động.

### 5.3 Quan hệ với Release / Board

- Không đổi `release_items`
- Issue CS/Sale vào sprint vẫn có thể gắn Release như issue Product
- Agile board: filter/badge source (Phase 2)

---

## 6. Phân phase

### Phase 1 — CS/Sale backlog view + nguồn issue (MVP)

**Scope**

- [x] Settings: bật CS/Sale backlog; `cs_queue_version_id` / `sale_queue_version_id`; CF `Intake source`
- [x] Routes + permissions: `view_cs_backlog`, `manage_cs_backlog`, `view_sale_backlog`, `manage_sale_backlog`
- [x] Trang CS/Sale: section **QUEUE** (Version) + **IN PRODUCT** (CF source)
- [x] Quick edit priority/SP/status trên QUEUE
- [x] Auto-create issue vào queue + set CF nguồn
- [x] Product backlog loại Version queue CS/Sale khỏi sprint sections
- [x] Badge nguồn trên Product backlog rows (Phase 1.1)
- [x] Locales en/vi + docs

**Non-goals Phase 1** (còn lại Phase 2+)

- Quota SP / pull wizard / auto-fill / watchers on pull
- Complete-sprint unfinished → Product backlog rule

**Acceptance criteria Phase 1**

1. CS chỉ thấy/manage lane CS (theo quyền); Sale tương tự.
2. Issue `source=cs` chưa có version hiện trên CS Backlog, không lẫn Product Backlog unscheduled (hoặc Product Backlog có filter ẩn CS/Sale mặc định).
3. Đổi priority trên CS Backlog → sort đổi đúng.
4. Product Backlog vẫn hoạt động như hiện tại với issue `source=product`.
5. Không regress Releases / sprint complete / global modal.

---

### Phase 2 — Sprint quota + PO intake (pull)

**Scope**

- [x] Mở rộng `sanan_agile_version_metas`: `cs_quota_sp`, `sale_quota_sp`
- [x] UI tạo/sửa sprint: nhập quota CS / Sale (+ default từ settings)
- [x] Panel **Pull from CS/Sale** trên Product Backlog (active/future sprint)
- [x] Validate remaining quota & (optional) sprint capacity khi add
- [x] Hiển thị used/remaining trên header sprint section
- [x] Bulk pull selected; optional “Auto-fill by priority until quota full”
- [x] Journal + **giữ CF Intake source** + **auto-add watchers** (mặc định)
- [x] CS/Sale section **IN PRODUCT** đầy đủ (sprint, status, assignee, progress)
- [x] Hạn chế edit CS khi issue đã IN PRODUCT (comment OK)
- [x] Badge nguồn trên Product backlog rows
- [x] Complete sprint: unfinished mặc định → Product backlog

**Acceptance criteria Phase 2**

1. Gán quota 10 SP CS; pull issue 3+3+5 → issue 5SP bị chặn hoặc cảnh báo vượt quota.
2. Auto-fill lấy theo Immediate→Low đến khi không đủ SP còn lại.
3. Issue đã pull có `fixed_version_id` đúng sprint; CF nguồn vẫn `cs`/`sale`; hiện trên CS/Sale **IN PRODUCT**.
4. CS mở ticket IN PRODUCT thấy status/assignee sprint hiện tại; không mất khỏi tầm nhìn sau khi PO lấy.
5. Complete sprint / report vẫn chạy; thống kê SP theo source (nice-to-have).

---

### Phase 3 — Báo cáo & tinh chỉnh

- [x] Sprint Close Report: breakdown SP/tickets theo Product / CS / Sale
- [x] Metrics: % capacity sprint dành cho CS/Sale (theo commit SP + quota)
- [x] SLA nhẹ trên CS (age in Ready queue)
- [x] Notify Product khi CS Ready queue vượt ngưỡng SP (banner + optional mail/ngày)
- [x] Filter source trên Issues (Intake source query filter)

---

## 7. Quyền & roles (gợi ý)

| Permission | CS | Sale | **PO** | Dev / SM |
|---|---|---|---|---|
| `view_cs_backlog` | ✓ | | ✓ | optional |
| `manage_cs_backlog` | ✓ | | optional | |
| `view_sale_backlog` | | ✓ | ✓ | optional |
| `manage_sale_backlog` | | ✓ | optional | |
| `manage_backlog` (Product backlog) | | | ✓ | SM optional |
| `pull_intake_to_sprint` | | | **✓ (chính)** | |

**PO** là actor chính cho intake: chọn ticket từ CS/Sale → Product sprint hoặc Product backlog.  
`pull_intake_to_sprint` có thể gộp vào `manage_backlog` nếu team gán quyền đó cho role PO.

---

## 8. API / routes (phác thảo)

| Method | Path | Mô tả |
|---|---|---|
| GET | `/projects/:id/cs_backlog` | HTML CS backlog |
| GET | `/projects/:id/sale_backlog` | HTML Sale backlog |
| POST | `/projects/:id/backlog/quick_update` | Tái dụng (đã có) |
| POST | `/projects/:id/backlog/pull_intake` | `{ version_id, issue_ids[], source: cs\|sale }` |
| PATCH | `/projects/:id/backlog/sprint_quota` | `{ version_id, cs_quota_sp, sale_quota_sp }` |

Files dự kiến:

```
docs/CS_SALE_BACKLOG_PLAN.md          # file này
app/controllers/cs_backlogs_controller.rb
app/controllers/sale_backlogs_controller.rb
# hoặc BacklogsController + param source=
lib/sanan_agile/intake_backlog_query.rb
app/views/cs_backlogs/show.html.erb
app/views/sale_backlogs/show.html.erb
db/migrate/xxxx_add_intake_quotas_to_sanan_agile_version_metas.rb
```

Tái dụng tối đa: `backlog.js` (cell menu), `backlogs_helper`, `BacklogQuery` với filter `source`.

---

## 9. Rule nghiệp vụ chi tiết (Phase 2)

### Pull validation

1. Issue `source` ∈ {cs, sale} đúng lane đang pull.
2. Issue ở trạng thái Ready (nếu cấu hình `ready_status_ids`).
3. Issue chưa thuộc sprint khác (hoặc cho phép move nếu SM confirm).
4. `sum(SP selected) ≤ remaining_quota(source, sprint)`.
5. Optional: `sum(SP selected) ≤ remaining_sprint_capacity` (nếu Product đặt capacity tổng).

### Priority ordering

```
ORDER BY priority.position_name (Immediate→Low),
         agile_data.position DESC NULLS LAST,
         issues.id ASC
```

### Khi hết quota

- UI disable checkbox issue làm vượt quota
- Auto-fill dừng ở issue không đủ chỗ
- Vẫn cho phép Product **override** (permission) kèm warning — cấu hình `allow_quota_override`

---

## 10. Rủi ro & mitigation

| Rủi ro | Mitigation |
|---|---|
| Lẫn issue CS vào Product Backlog | Filter mặc định `source=product` trên Product backlog; badge rõ |
| CS gắn thẳng vào sprint/backlog Product | Chỉ **PO** được intake; CS backlog ẩn/disable đổi sang Product sprint |
| SP trống → quota vô nghĩa | Bắt buộc SP khi chuyển Ready; hoặc treat blank = 0 / block |
| Hai team sửa cùng issue | Quyền theo source; journal đầy đủ |
| Quota quá cứng làm kẹt hotfix | `allow_quota_override` + audit |
| CF vs tracker mapping lệch | Phase 1 dùng Version queue — không phụ thuộc CF |
| Nhầm Version queue thành Product sprint | Settings gắn `cs_queue_version_id`; meta `is_product_sprint`; UI ẩn queue khỏi “Start sprint” |

---

## 11. Thứ tự triển khai đề xuất

1. Chốt phần còn lại ở §13 (Ready / hotfix / complete sprint)
2. Settings: chọn `cs_queue_version_id` / `sale_queue_version_id` + permissions + menu stub
3. Trang CS/Sale backlog = list issue theo Version queue, sort priority, hiện SP
4. Quick edit priority/SP/status trên lane
5. Product backlog: loại Version queue CS/Sale khỏi section sprint Product; badge nguồn theo queue/origin
6. Migration `cs_quota_sp` / `sale_quota_sp` trên version meta + UI Product sprint
7. Pull panel: chuyển Version queue → Product sprint + validate quota SP + auto-fill
8. Report breakdown SP theo CS / Sale / Product
9. QA với 3 role: CS, Sale, Product

---

## 12. Out of scope (có chủ đích)

- Portal khách hàng tự tạo ticket (ngoài Redmine)
- Workflow CS full (SLA engine, chatbot)
- Cross-company multi-backlog portfolio
- Thay Product Backlog / Releases hiện có

---

## 13. Quyết định đã chốt (checklist)

Không còn open question blockers.

| # | Quyết định |
|---|---|
| 1 | Issue mới CS/Sale → **auto** Version queue + CF `Intake source` |
| 2 | PO chỉ thấy candidate **Ready** |
| 3 | Hotfix **không** bypass quota (vẫn cần SP) |
| 4 | Unfinished lúc complete sprint → **Product backlog** |
| 5 | **3 menu riêng**; CS/Sale không thấy phần Product |
| 6 | Quota SP **chỉ trừ khi vào Product sprint** (vào backlog Product → không trừ) |
| 7 | IN PRODUCT: CS/Sale **chỉ comment** (+ xem) |
| 8 | PO pull → **auto-add watchers** (author/assignee nguồn), mặc định bật |

Cùng với: cùng project · quota = SP · Version queue CS/Sale · PO intake · IN PRODUCT + CF `Intake source`.

---

## 14. Thành công đo được

- CS/Sale tự quản lý hàng đợi; sau khi PO lấy vẫn **theo dõi tiến độ** trên cùng backlog (IN PRODUCT).
- **PO** chọn đúng ticket ưu tiên trong **quota SP**.
- Báo cáo sprint: SP intake từ CS / Sale / Product.
- Không regress backlog Product, board, releases.

---

## 15. Liên kết

- Product backlog hiện tại: `docs/BACKLOG_PLAN.md`
- Sprint close report: `docs/SPRINT_CLOSE_REPORT_PLAN.md`
