(function () {
  // ---------- helpers ----------
  function parseCard(html) {
    const tmp = document.createElement('div');
    tmp.innerHTML = (html || '').trim();
    return tmp.querySelector('.issue-card') || tmp.firstElementChild;
  }

  function findCard(id) {
    return document.querySelector('.issue-card[data-id="' + id + '"]');
  }

  function findTargetCol(statusId) {
    return (
      document.querySelector('td.issue-status-col[data-id="' + statusId + '"] .ui-sortable') ||
      document.querySelector('td.issue-status-col[data-id="' + statusId + '"]')
    );
  }

  function refreshSortable() {
    if (window.jQuery && jQuery.fn.sortable) jQuery('.ui-sortable').sortable('refresh');
  }

  function updateCountForHeader(statusId, newCount, isStickyHeader) {
    const th = document.querySelector(
      `table.list.issues-board${isStickyHeader ? '.sticky' : ':not(.sticky)'} th[data-column-id="${statusId}"]`
    );
    if (!th) return;

    let countSpan = th.querySelector('span.count');
    if (!countSpan) {
      // chèn "(<span class='count'></span>)" cuối tiêu đề nếu chưa có
      th.appendChild(document.createTextNode(' ('));
      countSpan = document.createElement('span');
      countSpan.className = 'count';
      th.appendChild(countSpan);
      th.appendChild(document.createTextNode(')'));
    }
    countSpan.textContent = String(newCount);
  }

  function updateHeaderCountFor(statusId) {
    if (!statusId) return;

    // body: đếm số card trong cột
    const bodyCol = document.querySelector(
      `table.list.issues-board:not(.sticky) td.issue-status-col[data-id="${statusId}"]`
    );
    const newCount = bodyCol ? bodyCol.querySelectorAll('.issue-card').length : 0;

    // header: tìm <th data-column-id="..."> và <span class="count">
    updateCountForHeader(statusId, newCount, false)
    updateCountForHeader(statusId, newCount, true)
  }

  // Gọi hàm này khi bạn move/replace card:
  // - oldStatusId: cột trước khi đổi
  // - newStatusId: cột sau khi đổi
  function updateHeaderCounts(oldStatusId, newStatusId) {
    if (oldStatusId) updateHeaderCountFor(oldStatusId);
    if (newStatusId && newStatusId !== oldStatusId) updateHeaderCountFor(newStatusId);
  }

  function highlight(el) {
    if (!el) return;
    el.classList.add('sanan-updated');
    setTimeout(function () {
      el.classList.remove('sanan-updated');
    }, 1200);
  }

  async function fetchCardHTML(issueId, opts) {
    // endpoint của plugin để render lại card theo context
    const url = new URL('/agile/board', window.location.origin);
    url.searchParams.set('id', issueId);
    if (opts && opts.projectId) url.searchParams.set('project_id', opts.projectId);
    if (opts && opts.queryId) url.searchParams.set('query_id', opts.queryId);
    var params = {
      issue: {
        status_id: opts.statusId
      },
      id: issueId,
      actor: $(".agile-board").data("actor")
    }

    const res = await $.ajax({
      url: url.toString(),
      type: 'PUT',
      data: params,
    });

    return res
  }

  function placeCard(issueId, html, opts) {
    const newCard = parseCard(html);
    if (!newCard) return;

    const oldCard = findCard(issueId);
    const targetCol = findTargetCol(opts.statusId);

    if (targetCol && oldCard && oldCard.closest('td.issue-status-col') !== targetCol.closest('td.issue-status-col')) {
      oldCard.remove();
      targetCol.appendChild(newCard);
    } else if (oldCard) {
      oldCard.replaceWith(newCard);
    } else if (targetCol) {
      targetCol.appendChild(newCard);
    }

    refreshSortable();
    updateHeaderCounts(opts.currentStatusId, opts.statusId);

    const mounted = findCard(issueId);
    if (opts && opts.scrollIntoView && mounted) {
      mounted.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
    if (!opts || opts.highlight !== false) highlight(mounted);
  }

  // ---------- PUBLIC API ----------
  // opts: { projectId?, queryId?, scrollIntoView?: true/false, highlight?: true/false }
  async function SANAN_refreshIssueCard(issueId, opts) {
    const newHtml = await fetchCardHTML(issueId, opts || {})
    // const statusId = json.issue.status.id;
    placeCard(issueId, newHtml, opts || {});
  }

  window.SANAN_refreshIssueCard = SANAN_refreshIssueCard;

  // CSS highlight nhỏ
  (function injectCSS() {
    const css = `
      .issue-card.sanan-updated { animation: sananPulse 1.2s ease-out; }
      @keyframes sananPulse { 0%{ box-shadow:0 0 0 0 rgba(255,230,100,.9); }
                              100%{ box-shadow:0 0 0 14px rgba(255,230,100,0); } }`;
    const s = document.createElement('style');
    s.textContent = css;
    document.head.appendChild(s);
  })();
})();
