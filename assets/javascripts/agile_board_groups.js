/* Agile board column groups: a header row grouping the status columns into
 *   Development — by default the commit "development" statuses (set A),
 *   UAT         — by default the other open statuses,
 *   Closed      — by default the closed statuses (Close, Rejected…): the end of every flow,
 * (statuses per group can be set in the settings) with per-group ticket / SP counts. Every group collapses
 * into a narrow strip — the group's first column stays
 * as a drop target, so dropping a card on the strip moves it to that status through the board's own drag & drop.
 * Config: window.SA_BOARD_GROUPS (app/views/sanan_agile/_board_column_groups.html.erb). */
(function (w, $) {
  'use strict';
  if (!$) return;

  var GROUPS = ['dev', 'uat', 'closed'];
  var COLLAPSIBLE = ['dev', 'uat', 'closed'];
  var COLLAPSED_BY_DEFAULT = { dev: false, uat: false, closed: true };

  var cfg = null;
  var collapsed = { dev: false, uat: false, closed: true };

  function t(key) { return (cfg.labels && cfg.labels[key]) || key; }

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function storeKey(group) { return 'sa-board-' + group + '-collapsed:' + cfg.projectKey; }

  function readCollapsed(group) {
    var v = null;
    try { v = localStorage.getItem(storeKey(group)); } catch (e) { v = null; }
    return v === null ? COLLAPSED_BY_DEFAULT[group] : v === '1';
  }

  function writeCollapsed(group, v) {
    try { localStorage.setItem(storeKey(group), v ? '1' : '0'); } catch (e) { /* ignore */ }
  }

  function mainTable() { return document.querySelector('table.issues-board:not(.sticky)'); }

  function tables() {
    return Array.prototype.slice.call(document.querySelectorAll('table.issues-board'));
  }

  function columnIds() {
    var table = mainTable();
    if (!table) return [];
    return Array.prototype.map.call(table.querySelectorAll('thead tr:not(.sa-col-groups) th[data-column-id]'),
      function (th) { return parseInt(th.getAttribute('data-column-id'), 10); });
  }

  // Status → group, resolved on the server (settings, else closed / set A / rest).
  function groupOf(id) {
    var map = cfg.statusGroups || {};
    return map[id] || map[String(id)] || 'uat';
  }

  // Mark every header / body cell with its group; each collapsible group's first column is its strip.
  function markCells() {
    var first = {};
    columnIds().forEach(function (id) {
      var g = groupOf(id);
      if (first[g] === undefined) first[g] = id;
    });
    tables().forEach(function (table) {
      table.querySelectorAll('th[data-column-id], td.issue-status-col[data-id]').forEach(function (cell) {
        var id = parseInt(cell.getAttribute('data-column-id') || cell.getAttribute('data-id'), 10);
        if (isNaN(id)) return;
        var g = groupOf(id);
        GROUPS.forEach(function (key) {
          cell.classList.toggle('sa-col--' + key, key === g);
          cell.classList.toggle('sa-col--' + key + '-first', key === g && first[key] === id);
        });
        cell.classList.toggle('sa-col--strip', COLLAPSIBLE.indexOf(g) !== -1 && first[g] === id);
        cell.classList.toggle('sa-col--collapsed', COLLAPSIBLE.indexOf(g) !== -1 && collapsed[g]);
      });
      COLLAPSIBLE.forEach(function (key) { table.classList.toggle('sa-' + key + '-collapsed', collapsed[key]); });
    });
  }

  function visible(el) { return el && w.getComputedStyle(el).display !== 'none'; }

  function groupStats(group) {
    var table = mainTable();
    var cards = 0;
    var sp = 0;
    if (!table) return { cards: 0, sp: 0 };
    table.querySelectorAll('td.issue-status-col.sa-col--' + group).forEach(function (col) {
      col.querySelectorAll('.issue-card[data-id]').forEach(function (card) {
        if (card.classList.contains('sa-hidden-by-source') || card.classList.contains('sa-hidden-by-release') ||
            card.classList.contains('sa-hidden-by-intake') || card.classList.contains('sa-hidden-by-epic')) return;
        cards += 1;
        sp += parseFloat(card.getAttribute('data-story-points') || '0') || 0;
      });
    });
    return { cards: cards, sp: Math.round(sp * 10) / 10 };
  }

  function groupLabel(group) {
    var s = groupStats(group);
    return '<span class="sa-col-groups__label"><span class="sa-col-groups__name">' + esc(t(group)) + '</span>' +
      '<span class="sa-col-groups__count">' + s.cards + (s.sp > 0 ? ' · ' + s.sp + 'sp' : '') + '</span></span>';
  }

  function toggleButton(group) {
    var c = collapsed[group];
    return '<button type="button" class="sa-col-groups__toggle" data-sa-group="' + group + '" aria-expanded="' + (!c) +
      '" title="' + esc(t((c ? 'expand_' : 'collapse_') + group)) + '">' + (c ? '&#8676;' : '&#8677;') + '</button>';
  }

  // Header row: one cell per contiguous run of columns of the same group (only visible columns count).
  function renderGroupRow() {
    tables().forEach(function (table) {
      var head = table.querySelector('thead');
      var leafRow = head && head.querySelector('tr:not(.sa-col-groups)');
      if (!leafRow) return;
      var row = head.querySelector('tr.sa-col-groups');
      if (!row) {
        row = document.createElement('tr');
        row.className = 'sa-col-groups';
        head.insertBefore(row, leafRow);
      }
      var runs = [];
      Array.prototype.forEach.call(leafRow.children, function (th) {
        if (!visible(th)) return;
        var group = 'other';
        GROUPS.forEach(function (key) { if (th.classList.contains('sa-col--' + key)) group = key; });
        var last = runs[runs.length - 1];
        if (last && last.group === group) last.span += 1;
        else runs.push({ group: group, span: 1 });
      });
      var html = runs.map(function (run) {
        if (run.group === 'other') return '<th colspan="' + run.span + '"></th>';
        var canCollapse = COLLAPSIBLE.indexOf(run.group) !== -1;
        var btn = canCollapse ? toggleButton(run.group) : '';
        var strip = canCollapse && collapsed[run.group];
        return '<th colspan="' + run.span + '" class="sa-col-groups__cell sa-col-groups__cell--' + run.group + '">' +
          (strip ? '<div class="sa-col-groups__inner sa-col-groups__inner--strip">' + btn + '</div>'
                 : '<div class="sa-col-groups__inner">' + groupLabel(run.group) + btn + '</div>') +
          '</th>';
      }).join('');
      // Only touch the DOM when the row changes (keeps the toggle button stable under the pointer).
      if (row._saHtml !== html) {
        row._saHtml = html;
        row.innerHTML = html;
      }
    });
  }

  // Collapsed group: a vertical "UAT · n" label at the top of its strip (the group's first column cells).
  function renderStripLabels() {
    var table = mainTable();
    if (!table) return;
    COLLAPSIBLE.forEach(function (group) {
      var text = t(group) + ' · ' + groupStats(group).cards;
      table.querySelectorAll('td.issue-status-col.sa-col--' + group + '-first').forEach(function (td) {
        var label = td.querySelector(':scope > .sa-strip-label');
        if (!collapsed[group]) { if (label) label.remove(); return; }
        if (!label) {
          label = document.createElement('div');
          label.className = 'sa-strip-label';
          label.setAttribute('data-sa-group', group);
          td.insertBefore(label, td.firstChild);
        }
        if (label.textContent !== text) label.textContent = text;
        label.title = t('expand_' + group);
      });
    });
  }

  // Keep each group's name in view while the board scrolls horizontally: shift it by the wrapper's scroll
  // (CSS sticky does not take effect in these header cells, nor in the fixed header clone).
  function syncGroupLabels() {
    var wrapper = document.querySelector('div.agile-board-scroll-wrapper');
    if (!wrapper) return;
    var scroll = wrapper.scrollLeft;
    document.querySelectorAll('table.issues-board tr.sa-col-groups th.sa-col-groups__cell').forEach(function (th) {
      var label = th.querySelector('.sa-col-groups__label');
      if (!label) return;
      var room = th.offsetWidth - label.offsetWidth - 60;
      var shift = Math.max(0, Math.min(scroll - th.offsetLeft, room));
      label.style.transform = shift > 0 ? 'translateX(' + shift + 'px)' : '';
    });
  }

  function refresh() {
    if (!cfg) return;
    markCells();
    renderGroupRow();
    renderStripLabels();
    syncGroupLabels();
  }

  var refreshSoon = (function () {
    var timer = null;
    return function () {
      clearTimeout(timer);
      timer = setTimeout(refresh, 120);
    };
  })();

  function setCollapsed(group, v) {
    if (COLLAPSIBLE.indexOf(group) === -1) return;
    collapsed[group] = !!v;
    writeCollapsed(group, collapsed[group]);
    refresh();
    try { w.dispatchEvent(new Event('resize')); } catch (e) { /* ignore */ }
  }

  function observe() {
    var table = mainTable();
    if (!table || table._saGroupsObserved) return;
    table._saGroupsObserved = true;
    // Cards moved / added / filtered: recount the groups (our own strip labels excepted).
    new MutationObserver(function (muts) {
      for (var i = 0; i < muts.length; i++) {
        var m = muts[i];
        if (m.target.closest && (m.target.closest('tr.sa-col-groups') || m.target.closest('.sa-strip-label'))) continue;
        var added = Array.prototype.slice.call(m.addedNodes || []).concat(Array.prototype.slice.call(m.removedNodes || []));
        if (added.length && added.every(function (n) { return n.classList && n.classList.contains('sa-strip-label'); })) continue;
        refreshSoon();
        return;
      }
    }).observe(table.querySelector('tbody') || table, { childList: true, subtree: true, attributes: true, attributeFilter: ['class'] });
  }

  function boot() {
    cfg = w.SA_BOARD_GROUPS;
    if (!cfg || !cfg.statusGroups || !mainTable()) return;
    COLLAPSIBLE.forEach(function (group) { collapsed[group] = readCollapsed(group); });
    refresh();
    observe();
    if (!boot.bound) {
      boot.bound = true;
      $(document).on('click', '.sa-col-groups__toggle, .sa-strip-label', function (e) {
        e.preventDefault();
        var group = this.getAttribute('data-sa-group');
        setCollapsed(group, !collapsed[group]);
      });
      $(document).on('change', '#sa-board-view, #sa-source-filter, #sa-release-filter, #sa-intake-filter, #sa-epic-filter', refreshSoon);
      // The sticky header clone is created by redmine_agile on DOM ready; mark it once it exists.
      $(w).on('load', refresh);
      $('div.agile-board-scroll-wrapper').on('scroll', syncGroupLabels);
      $(w).on('scroll', syncGroupLabels);
      setTimeout(refresh, 0);
      setTimeout(refresh, 600);
    }
  }

  w.SananBoardGroups = { boot: boot, refresh: refresh };
  $(function () { boot(); });
})(window, window.jQuery);
