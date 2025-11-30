// plugin_assets/sanan_redmine_agile/javascripts/agile_release_badges.js
(function (U) {
  if (window.__saReleaseBadgesLoaded) return; // tránh nạp 2 lần
  window.__saReleaseBadgesLoaded = true;

  let mapIssueWithRelease = new Map()

  const projectId = (function () {
    const m = location.pathname.match(/\/projects\/([^\/]+)/);
    return m ? m[1] : null;
  })();

  // Tìm tất cả card và id issue
  function collectIssueEls() {
    // Card của redmine_agile thường có data-issue-id hoặc data-id
    const candidates = Array.from(document.querySelectorAll(
      '.agile-board .issue-card, .agile-board .issue, .agile-card'
    ));
    const pairs = [];
    for (const el of candidates) {
      const id = parseInt(el.getAttribute('data-issue-id') || el.getAttribute('data-id'), 10);
      if (!isNaN(id)) pairs.push({ el, id });
    }
    return dedupById(pairs);
  }

  function dedupById(pairs) {
    const seen = new Set();
    return pairs.filter(p => !seen.has(p.id) && seen.add(p.id));
  }

  // Tạo khu vực để đặt badge trên 1 card (nếu chưa có)
  function ensureExtraWrap(el) {
    // thử tìm khu attributes/footer trong card
    let container = el.querySelector('.sa-card-extra');
    if (!container) {
      container = document.createElement('div');
      container.className = 'sa-card-extra';
      // chèn sau attributes, fallback là chèn cuối card
      const attr = el.querySelector('.attributes, .info, .details, .issue-card-details');
      if (attr && attr.parentNode) attr.parentNode.appendChild(container);
      else el.appendChild(container);
    }
    return container;
  }

  // Gọi API lấy mapping
  async function fetchUnreleasedMap() {
    const url = `/projects/${projectId}/release_badges/unreleased_map`;
    const res = await fetch(url, {
      headers: { 'Accept': 'application/json', 'X-Requested-With': 'XMLHttpRequest' },
      credentials: 'same-origin'
    });
    if (!res.ok) return [];
    return res.json(); // [{issue_id, releases:[{id,name}, ...]}, ...]
  }

  const reconcile = (mapIssueWithRelease, ensureExtraWrap) => (card) => {
    // Nếu chưa có map thì thôi (chưa fetch xong)
    if (!mapIssueWithRelease || mapIssueWithRelease.size === 0) return;

    const rawId = U.findIssueId(card);
    if (!rawId) return;

    const id = parseInt(rawId, 10);
    if (isNaN(id)) return;

    const parentId = parseInt(card.getAttribute('data-parent-id'), 10);
    const entry = mapIssueWithRelease.get(id) || (parentId ? mapIssueWithRelease.get(parentId) : null);

    const newReleaseIds = entry ? entry.releases.map(r => r.id).join(',') : '';
    const newReleaseNames = entry ? entry.releases.map(r => r.name).join('||') : '';

    // Nếu không đổi gì so với trước thì không động vào DOM (idempotent)
    if (card.dataset.releaseIds === newReleaseIds && card.dataset.releaseNames === newReleaseNames) {
      return;
    }

    card.dataset.releaseIds = newReleaseIds;
    card.dataset.releaseNames = newReleaseNames;

    const host = ensureExtraWrap(card);
    let wrap = host.querySelector('.sa-release-badges-wrap');

    // Nếu không có release nào → xoá wrap nếu có rồi thôi
    if (!entry || !entry.releases || entry.releases.length === 0) {
      if (wrap) wrap.remove();
      return;
    }

    if (!wrap) {
      wrap = document.createElement('div');
      wrap.className = 'sa-release-badges-wrap';
      host.appendChild(wrap);
    } else {
      // clear nội dung cũ
      while (wrap.firstChild) {
        wrap.removeChild(wrap.firstChild);
      }
    }

    entry.releases.forEach(r => {
      const b = document.createElement('span');
      b.className = 'sa-release-badge';
      b.dataset.tooltip = `In releases: ${escapeHtml(r.name)}`;
      b.title = r.name;
      b.innerHTML = `<span class="sa-dot"></span><span class="sa-txt">${escapeHtml(r.name)}</span>`;
      wrap.appendChild(b);
    });
  }

  function escapeHtml(s) { return String(s).replace(/[&<>"']/g, m => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[m])); }

  // Toolbar filter (client-side)
  function ensureFilterBar(allReleases) {
    // đặt trong header Agile (gần form filter có sẵn)
    let anchor = document.querySelector('.agile-board-header, .agile-board .query-totals, .agile-board');
    if (!anchor) anchor = document.querySelector('#content');

    if (!document.getElementById('sa-release-filterbar')) {
      const bar = document.createElement('div');
      bar.id = 'sa-release-filterbar';
      bar.innerHTML = `
        <label for="sa-release-filter"><strong>Release:</strong></label>
        <select id="sa-release-filter">
          <option value="">All releases</option>
        </select>
        <button id="sa-release-clear" type="button">Clear</button>
      `;
      anchor.prepend(bar);
    }

    const sel = document.getElementById('sa-release-filter');
    // Build options duy nhất, sort theo tên
    const unique = Array.from(new Map(allReleases.map(r => [r.id, r])).values())
      .sort((a, b) => String(a.name).localeCompare(String(b.name)));

    // fill
    const current = sel.value;
    sel.innerHTML = `<option value="">All releases</option>` +
      unique.map(r => `<option value="${r.id}">${escapeHtml(r.name)}</option>`).join('');
    // giữ lại chọn hiện tại nếu còn tồn tại
    if (unique.some(r => String(r.id) === current)) sel.value = current;

    // bind
    if (!sel._saBound) {
      sel._saBound = true;
      sel.addEventListener('change', applyFilter);
      document.getElementById('sa-release-clear').addEventListener('click', () => {
        sel.value = '';
        applyFilter();
      });
    }
  }

  function applyFilter() {
    const value = document.getElementById('sa-release-filter').value;
    const cards = collectIssueEls().map(p => p.el);
    if (!value) {
      cards.forEach(el => el.classList.remove('sa-hidden-by-release'));
      return;
    }
    cards.forEach(el => {
      const ids = (el.dataset.releaseIds || '').split(',').filter(Boolean);
      if (ids.includes(String(value))) el.classList.remove('sa-hidden-by-release');
      else el.classList.add('sa-hidden-by-release');
    });
  }

  // Kick
  document.addEventListener('DOMContentLoaded', async () => {
    dataRelease = await fetchUnreleasedMap();
    if (!dataRelease?.length) {
      return;
    }

    const listAllReleases = [];
    dataRelease.forEach(row => {
      mapIssueWithRelease.set(row.issue_id, row);
      (row.releases || []).forEach(r => listAllReleases.push(r));
    });

    ensureFilterBar(listAllReleases);

    U.register(reconcile(mapIssueWithRelease, ensureExtraWrap));
    U.boot();
  });
})(window.SananAgileUtil);
