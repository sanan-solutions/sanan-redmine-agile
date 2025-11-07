///////////////// FOR SHOW SCREEN /////////////////////
(function () {
  const token = document.querySelector('meta[name="csrf-token"]')?.content;
  const base = window.location.pathname; // /projects/:pid/releases/:id
  const table = document.getElementById('wi-table');
  if (!table) return;
  const tbody = table.querySelector('tbody');

  // --- TOGGLE children ---
  document.querySelectorAll('.tree-toggle').forEach(tgl => {
    const row = tgl.closest('.wi-row');
    const id = row.dataset.id;
    const hasChildren = tbody.querySelector(`.wi-row[data-parent-id="${id}"]`);
    if (!hasChildren) { tgl.textContent = ''; return; }

    tgl.textContent = '▾';
    tgl.classList.add('toggleable');
    row.classList.add('has-children'); // <— thêm class nhận diện

    tgl.addEventListener('click', () => {
      const expanded = tgl.textContent === '▾';
      const children = tbody.querySelectorAll(`.wi-row[data-parent-id="${id}"]`);
      children.forEach(ch => ch.style.display = expanded ? 'none' : '');
      tgl.textContent = expanded ? '▸' : '▾';
      row.classList.toggle('collapsed', expanded); // <— để CSS xoay caret
    });
  });

  // --- Edit modal
  const editBtn = document.getElementById('btn-edit-release');
  const editModal = document.getElementById('edit-modal');
  const editBody = document.getElementById('edit-modal-body');

  if (editBtn && editModal && editBody) {
    editBtn.addEventListener('click', async () => {
      const html = await fetch(base + '/edit', { headers: { 'X-Requested-With': 'XMLHttpRequest' } }).then(r => r.text());
      editBody.innerHTML = html;
      editModal.hidden = false;
      const form = editBody.querySelector('#rel-edit-form');
      form.addEventListener('submit', async (e) => {
        e.preventDefault();
        const fd = new FormData(form);
        const res = await fetch(form.action, {
          method: 'PUT', // Rails UJS sẽ hiểu data-method, nhưng ta patch trực tiếp:
          headers: { 'X-CSRF-Token': token },
          body: fd
        }).then(r => r.json());
        if (res.ok) location.reload();
        else alert(res.errors?.join('\n') || 'Update failed');
      });
    });

    editModal.addEventListener('click', (e) => {
      if (e.target.classList.contains('modal__close') || e.target === editModal) editModal.hidden = true;
    });
  }

  const stateSel = document.getElementById('release-state-select');
  if (stateSel) {
    let previous = stateSel.dataset.current || stateSel.value;
    const labelOf = (st) => st === 'released' ? 'Released' : st === 'archived' ? 'Archived' : 'Unreleased';

    stateSel.addEventListener('change', async (e) => {
      const next = e.target.value;
      const noteForReleased =
        `We’ll validate sub-issues and required statuses. If all checks pass,
       items will be updated accordingly (workflow bypass).`;

      const dlg = SA.showConfirm({
        title: 'Confirm change',
        desc: `You’re about to set this release to <strong>${labelOf(next)}</strong>.`,
        note: next === 'released' ? noteForReleased : '',
        confirmText: 'Confirm',
        cancelText: 'Cancel'
      });

      dlg.onCancel(() => { stateSel.value = previous; });
      dlg.onConfirm(async () => {
        const handleError = (message) => {
          const timeout = setTimeout(() => {
            saHideLoading();
            stateSel.disabled = false;
            saAlertError('Conflict: ', message || 'Cannot change state.');
            // revert UI về trạng thái cũ
            const current = stateSel.getAttribute('data-current');
            if (current) stateSel.value = current;
            clearTimeout(timeout)
          }, 300);
        }

        try {
          stateSel.disabled = true;
          dlg.close();
          saShowLoading('Changing release state…');

          const res = await fetch(base + '/change_state', {
            method: 'PATCH',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': token, 'Accept': 'application/json' },
            body: JSON.stringify({ state: stateSel.value })
          })
          const data = await res.json();

          if (!res.ok || data.ok === false) {
            handleError(data?.message)
            return;
          }

          // Thành công
          previous = next;
          // success → cập nhật data-current
          stateSel.setAttribute('data-current', data.state);

          const timeout = setTimeout(() => {
            saHideLoading();
            stateSel.disabled = false;
            location.reload();
            clearTimeout(timeout)
          }, 300)
        } catch (err) {
          handleError(err?.message)
        }
      });
    });
  }

  // Quick status change
  table.addEventListener('change', (e) => {
    if (!e.target.classList.contains('wi-status')) return;
    const tr = e.target.closest('.wi-row');
    fetch(base + '/update_issue_status', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': token, 'X-Requested-With': 'XMLHttpRequest' },
      body: JSON.stringify({ issue_id: tr.dataset.id, status_id: e.target.value })
    }).then(r => r.json()).then(j => {
      if (!j.ok) alert(j.errors?.join('\n') || 'Update failed');
      else tr.dataset.statusId = e.target.value;
    }).catch((err) => alert(JSON.stringify(err)))
  });

  // Remove from release
  table.addEventListener('click', (e) => {
    if (!e.target.classList.contains('wi-remove')) return;
    const tr = e.target.closest('.wi-row');
    const id = tr.dataset.id;
    if (!confirm('Remove this issue from release?')) return;
    fetch(base + '/detach_item?issue_id=' + tr.dataset.id, {
      method: 'DELETE', headers: { 'X-CSRF-Token': token, 'X-Requested-With': 'XMLHttpRequest' }
    }).then(() => {
      tr.remove();
      table.querySelectorAll(`tr.wi-row[data-parent-id="${id}"]`)?.forEach(item => item.remove())
    }).catch(() => alert('Network error'));
  });

  // --- FILTERS (only parents) ---
  const qInput = document.getElementById('wi-search');
  const stSel = document.getElementById('wi-status-filter');
  const asSel = document.getElementById('wi-assignee-filter');
  const trSel = document.getElementById('wi-tracker-filter');
  const prSel = document.getElementById('wi-priority-filter');
  const epicSel = document.getElementById('wi-epic-filter');
  const fromSprintSel = document.getElementById('wi-from-sprint-filter');
  const wiClear = document.getElementById('wi-clear');

  const allFilterInput = [stSel, asSel, trSel, prSel, epicSel, fromSprintSel]
  const allRows = Array.from(table.querySelectorAll('tr.wi-row'));
  const parentRows = Array.from(table.querySelectorAll('tr.wi-row-parent'));

  // Helper
  const text = (el, attr) => (el.dataset[attr] || '').trim();
  const uniqSorted = arr => Array.from(new Set(arr.filter(Boolean))).sort((a, b) => a.localeCompare(b));

  // 1) Build options cho filter từ **parent rows**
  (function buildFilterOptions() {
    const epics = uniqSorted(parentRows.map(r => r.dataset.epicLabel || ''));
    const trackers = uniqSorted(parentRows.map(r => r.dataset.sortTracker || ''));
    const priorities = uniqSorted(parentRows.map(r => r.dataset.sortPriority || ''));
    const statuses = uniqSorted(parentRows.map(r => r.dataset.sortStatus || ''));
    const assignees = uniqSorted(parentRows.map(r => r.dataset.sortAssignee || ''));
    const fromSprints = uniqSorted(parentRows.map(r => r.dataset.fromSprint || ''));

    // fill select (giữ option đầu)
    function fill(sel, values, labelize = (s) => s) {
      if (!sel) return;
      const first = sel.firstElementChild; // option đầu tiên (placeholder)
      sel.innerHTML = '';
      if (first) sel.appendChild(first);
      values.forEach(v => {
        const opt = document.createElement('option');
        opt.value = v;
        opt.textContent = labelize(v);
        sel.appendChild(opt);
      });
    }

    fill(epicSel, epics, s => s); // đã là label
    fill(trSel, trackers, s => s);
    fill(prSel, priorities, s => s);
    fill(stSel, statuses, s => s);
    fill(asSel, assignees, s => s);
    fill(fromSprintSel, fromSprints, s => s)

    // Nếu muốn filter Tracker/Priority theo “tên đúng”, bạn có thể dùng s.capitalize
    // Ở đây bạn đã có sẵn các select tracker/priority ở toolbar chính, nên có thể giữ nguyên hoặc điền lại tương tự.
  })();

  // 2) Apply filter (chỉ với parent); child ẩn/hiện theo parent
  function applyFilters() {
    const term = (qInput?.value || '').trim().toLowerCase();
    const stVal = stSel?.value || '';
    const asVal = asSel?.value || '';
    const trVal = trSel?.value || '';
    const prVal = prSel?.value || '';
    const epicVal = epicSel?.value || '';
    const fromSprintVal = fromSprintSel?.value || ''

    // Reset: ẩn tất cả -> sau đó xử lý parent rồi child theo parent
    allRows.forEach(r => r.style.display = 'none');

    parentRows.forEach(p => {
      // match text (summary), status, assignee, tracker, priority, epic
      const matchesText = !term || (p.dataset.sortSummary || '').includes(term) || p.querySelector('.wi-summary')?.textContent.toLowerCase().includes(term);
      const matchesStatus = !stVal || (p.dataset.sortStatus === stVal || (p.dataset.sortStatus || '') === stVal);
      const matchesAssign = !asVal || p.dataset.sortAssignee === asVal;
      const matchesTracker = !trVal || p.dataset.sortTracker === trVal;
      const matchesPrio = !prVal || p.dataset.sortPriority === prVal;
      const matchesEpic = !epicVal || (p.dataset.epicLabel || '') === epicVal;
      const matchesFromSprint = !fromSprintVal || (p.dataset.fromSprint || '') === fromSprintVal;

      const show = matchesText && matchesStatus && matchesAssign && matchesTracker && matchesPrio && matchesEpic && matchesFromSprint;

      if (show) {
        p.style.display = '';
        // show children of this parent
        const pid = p.dataset.id;
        allRows.forEach(ch => {
          if (ch.dataset.parentId === pid) ch.style.display = '';
        });
      }
    });
  }

  // Clear toàn bộ filter về mặc định và áp lại
  wiClear && wiClear.addEventListener('click', () => {
    if (qInput) qInput.value = '';
    allFilterInput.forEach(sel => { if (sel) sel.value = ''; });
    applyFilters();
    // (tuỳ chọn) scroll lên đầu bảng sau khi clear:
    // table.closest('.work-items')?.scrollTo({ top: 0, behavior: 'smooth' });
  });

  // 3) Events (debounce cho search)
  let t;
  qInput && qInput.addEventListener('input', () => { clearTimeout(t); t = setTimeout(applyFilters, 180); });
  allFilterInput.forEach(sel => sel && sel.addEventListener('change', applyFilters));

  applyFilters(); // lần đầu
})();

////////////////////////////////////// FOR PICKER MODAL /////////////////////////////////////////
(function () {
  const base = window.location.pathname; // /projects/:pid/releases/:id
  const token = document.querySelector('meta[name="csrf-token"]')?.content;
  // ---- PICKER (client-side filtering) ----
  const pkModal = document.getElementById('picker-modal');
  const pkBody = document.getElementById('pk-tbody');
  const pkBtn = document.getElementById('btn-add-items') || document.getElementById('btn-add-items'); // tuỳ bạn đã đặt id
  const pkAttach = document.getElementById('pk-attach');

  // filters
  const pkQ = document.getElementById('pk-q');
  const pkEpic = document.getElementById('pk-epic');
  const pkTracker = document.getElementById('pk-tracker');
  const pkPriority = document.getElementById('pk-priority');
  const pkRelease = document.getElementById('pk-release');
  const pkStatus = document.getElementById('pk-status');
  const pkFromSprint = document.getElementById('pk-from-sprint');
  const pkClear = document.getElementById('pk-clear');

  let pkAll = []; // toàn bộ issues (fetch 1 lần khi mở modal)
  let pkFilter = { q: '', epic: '', tracker: '', priority: '', release: '', status: '', fromSprint: '' };

  const priorityMap = { "Low": "lowest", "Normal": "default", "High": "high3", "Urgent": "high2", "Immediate": "highest" };

  const escapeHtml = (s) => {
    return (s || '').replace(/[&<>"']/g, m => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[m]));
  }

  const populateFilterOptions = () => {
    const sets = { epic: new Set(), tracker: new Set(), priority: new Set(), release: new Set(), status: new Set(), fromSprint: new Set() };
    pkAll.forEach(r => {
      if (r.epic) sets.epic.add(r.epic);
      if (r.tracker) sets.tracker.add(r.tracker);
      if (r.priority) sets.priority.add(r.priority);
      if (r.release_name) sets.release.add(r.release_name);
      if (r.status) sets.status.add(r.status);
      if (r.from_sprint_name) sets.fromSprint.add(r.from_sprint_name)
    });
    // helper
    const fill = (sel, values) => {
      sel.innerHTML = `<option value="">All ${sel.id.replace('pk-', '')}s</option>`;
      console.log('enenenen', sel, pkFromSprint, sel === pkFromSprint)
      if (sel.id == pkRelease.id) {
        const o = document.createElement('option');
        o.value = '-';
        o.textContent = 'Not in release';
        sel.appendChild(o);
      }
      [...values].sort().forEach(v => {
        const o = document.createElement('option');
        o.value = v;
        o.textContent = v;
        sel.appendChild(o);
      });
    };
    fill(pkEpic, sets.epic);
    fill(pkTracker, sets.tracker);
    fill(pkPriority, sets.priority);
    fill(pkRelease, sets.release);
    fill(pkFromSprint, sets.fromSprint)
    fill(pkStatus, sets.status);
  }

  const applyFilters = () => {
    const q = pkFilter.q.toLowerCase();
    return pkAll.filter(r => {
      return (!q || r.subject.toLowerCase().includes(q) || (`#${r.id}`).includes(q)) &&
        (!pkFilter.epic || r.epic === pkFilter.epic) &&
        (!pkFilter.tracker || r.tracker === pkFilter.tracker) &&
        (!pkFilter.priority || r.priority === pkFilter.priority) &&
        (!pkFilter.release || (r.release_name ?? '-') === pkFilter.release) &&
        (!pkFilter.status || r.status === pkFilter.status) &&
        (!pkFilter.fromSprint || r.from_sprint_name === pkFilter.fromSprint);
    });
  }

  const renderPickerRows = (rows) => {
    pkBody.innerHTML = rows.map(row => {
      const disabled = row.in_current_release;
      return `
        <tr>
          <td><input type="checkbox" class="pk-chk" ${disabled ? 'disabled' : ''} value="${row.id}"></td>
          <td>#${row.id}</td>
          <td>${row.tracker || '-'}</td>
          <td class="wi-summary">
            <div class="wrap">${escapeHtml(row.subject)}</div>
          </td>
          <td class="wi-epic">
            ${row.epic
          ? `<span class="badge badge-epic" data-tooltip="Epic${escapeHtml(row.epic)}">
                        <span class="badge-text">${escapeHtml(row.epic)}</span>
                      </span>`
          : '-'
        }
          </td>
          <td>
            ${row.from_sprint_name ? `<span class="badge badge-version sa-ellipsis">${row.from_sprint_name}</span>` : '-'}
          </td>
          <td class="sanan-agile-priority">
            <div class="priority priority-${priorityMap[row.priority] || 'default'}" title="Priority: ${row.priority || ''}"></div>
            ${row.priority || '-'}
          </td>
          <td>${row.status || '-'}</td>
          <td>${row.assignee || '-'}</td>
          <td class="col-release">
            ${row.release_id
          ? `<span class="badge badge-release ${row.in_current_release ? 'is-current' : ''}"
                            data-tooltip="${row.in_current_release ? 'Already in this release' : 'Release: ' + escapeHtml(row.release_name)}">
                        <span class="badge-text">${row.in_current_release ? 'CURRENT' : escapeHtml(row.release_name)}</span>
                      </span>`
          : '-'
        }
          </td>
        </tr>`;
    }).join('');
  }

  const loadPickerAll = async () => {
    // lấy id release hiện tại để server gắn in_current_release
    const relId = (base.match(/releases\/(\d+)/) || [])[1];
    const url = new URL(location.origin + base.replace(/\/releases\/\d+.*/, '') + '/releases/issues_search');
    if (relId) url.searchParams.set('exclude_release_id', relId);
    // Không truyền q/status -> server trả ALL (giới hạn hợp lý, vd 1000)
    const data = await fetch(url.toString(), { headers: { 'X-Requested-With': 'XMLHttpRequest' } }).then(r => r.json());
    pkAll = data;
    populateFilterOptions();
    renderPickerRows(applyFilters());
  }

  // debounce search
  let pkTimer = null;
  const onSearchInput = (e) => {
    pkFilter.q = e.target.value.trim();
    clearTimeout(pkTimer);
    pkTimer = setTimeout(() => renderPickerRows(applyFilters()), 250);
  }

  // filter change -> render ngay
  const onFilterChange = () => {
    pkFilter.epic = pkEpic.value;
    pkFilter.tracker = pkTracker.value;
    pkFilter.priority = pkPriority.value;
    pkFilter.release = pkRelease.value;
    pkFilter.status = pkStatus.value;
    pkFilter.fromSprint = pkFromSprint.value;
    renderPickerRows(applyFilters());
  }

  // clear nhanh
  const onClear = () => {
    pkFilter = { q: '', epic: '', tracker: '', priority: '', release: '', status: '', fromSprint: '' };
    pkQ.value = ''; pkEpic.value = ''; pkTracker.value = ''; pkPriority.value = ''; pkRelease.value = ''; pkStatus.value = ''; pkFromSprint.value = ''
    renderPickerRows(pkAll);
  }

  // OPEN/CLOSE
  const openPicker = () => { pkModal.hidden = false; loadPickerAll(); };
  const closePicker = (e) => { if (e.target.classList.contains('modal__close') || e.target === pkModal) pkModal.hidden = true; };

  pkBtn?.addEventListener('click', openPicker);
  pkModal?.addEventListener('click', closePicker);

  // events
  pkQ?.addEventListener('input', onSearchInput);
  [pkEpic, pkTracker, pkPriority, pkRelease, pkStatus, pkFromSprint].forEach(el => el?.addEventListener('change', onFilterChange));
  pkClear?.addEventListener('click', onClear);

  // attach
  pkAttach?.addEventListener('click', async () => {
    const ids = Array.from(pkBody.querySelectorAll('.pk-chk:checked')).map(i => i.value);
    if (ids.length === 0) { pkModal.hidden = true; return; }
    await fetch(base + '/attach_issues', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': token, 'X-Requested-With': 'XMLHttpRequest' },
      body: JSON.stringify({ issue_ids: ids })
    });
    location.reload();
  });
})();
