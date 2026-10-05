/* Agile board backlog panel: drag a ticket of the Product Backlog / an upcoming sprint onto a board column to
 * bring it into the board's sprint (status = the column). A small dialog asks the "This sprint" SP per team;
 * left blank, the ticket joins the sprint without being committed.
 * Config: window.SA_BOARD_BACKLOG (app/views/sanan_agile/_board_backlog_panel.html.erb). */
(function (w, $) {
  'use strict';
  if (!$) return;

  var cfg = null;
  var state = { source: 'backlog', q: '', trackerId: '', offset: 0, loading: false, hasMore: false, seq: 0 };

  function t(key) { return (cfg.labels && cfg.labels[key]) || key; }

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function csrf() { return $('meta[name="csrf-token"]').attr('content') || ''; }

  function storeKey() { return 'sa-board-backlog:' + cfg.projectKey; }

  function readOpen() {
    try { return localStorage.getItem(storeKey()) === '1'; } catch (e) { return false; }
  }

  function writeOpen(open) {
    try { localStorage.setItem(storeKey(), open ? '1' : '0'); } catch (e) { /* ignore */ }
  }

  function debounce(fn, ms) {
    var timer;
    return function () {
      var args = arguments;
      clearTimeout(timer);
      timer = setTimeout(function () { fn.apply(null, args); }, ms);
    };
  }

  // ----- layout -----------------------------------------------------------------------------------------

  function ensureLayout() {
    var $board = $('.agile-board').first();
    if (!$board.length) return null;
    var $layout = $board.closest('.sa-bb-layout');
    if ($layout.length) return $layout;
    $layout = $('<div class="sa-bb-layout"></div>');
    $board.before($layout);
    $layout.append(buildPanel()).append($board);
    return $layout;
  }

  function buildPanel() {
    var trackers = '<option value="">' + esc(t('allTrackers')) + '</option>' +
      (cfg.trackers || []).map(function (tr) {
        return '<option value="' + esc(tr.id) + '">' + esc(tr.name) + '</option>';
      }).join('');
    var hint = cfg.target
      ? esc(t('hint')).replace('__NAME__', '<strong>' + esc(cfg.target.name) + '</strong>')
      : esc(t('noTarget'));
    return $(
      '<aside class="sa-bb-panel" id="sa-bb-panel" hidden>' +
        '<div class="sa-bb-panel__head">' +
          '<strong class="sa-bb-panel__title">' + esc(t('title')) + '</strong>' +
          '<button type="button" class="sa-bb-panel__close" aria-label="' + esc(t('cancel')) + '">&times;</button>' +
        '</div>' +
        '<div class="sa-bb-panel__controls">' +
          '<label class="sa-bb-panel__label" for="sa-bb-source">' + esc(t('source')) + '</label>' +
          '<select id="sa-bb-source" class="sa-bb-panel__select"></select>' +
          '<input type="search" id="sa-bb-search" class="sa-bb-panel__input" placeholder="' + esc(t('search')) + '">' +
          '<select id="sa-bb-tracker" class="sa-bb-panel__select">' + trackers + '</select>' +
        '</div>' +
        '<p class="sa-bb-panel__hint' + (cfg.target ? '' : ' sa-bb-panel__hint--warn') + '">' + hint + '</p>' +
        '<p class="sa-bb-panel__error" id="sa-bb-error" hidden></p>' +
        '<div class="sa-bb-panel__list" id="sa-bb-list"></div>' +
        '<div class="sa-bb-panel__drop" aria-hidden="true"><span></span></div>' +
      '</aside>'
    );
  }

  var TOGGLE_ICON =
    '<svg class="sa-bb-toggle__icon" width="16" height="16" viewBox="0 0 16 16" aria-hidden="true" focusable="false">' +
      '<rect x="1.75" y="2.25" width="12.5" height="11.5" rx="2" fill="none" stroke="currentColor" stroke-width="1.5"/>' +
      '<path d="M6 2.5v11" stroke="currentColor" stroke-width="1.5"/>' +
      '<path d="M3.5 5.5h1M3.5 8h1M3.5 10.5h1" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>' +
    '</svg>';

  // First action of the board's top toolbar (before Sprint details / Complete sprint / New issue / Charts).
  function ensureToggle() {
    if (document.getElementById('sa-bb-toggle')) return;
    var $link = $('<a href="#" id="sa-bb-toggle" class="icon sa-bb-toggle" role="button" aria-controls="sa-bb-panel"></a>')
      .attr('title', t('toggle')).html(TOGGLE_ICON + '<span>' + esc(t('toggle')) + '</span>');
    var $bar = $('#content > .contextual').first();
    if ($bar.length) $bar.prepend($link);
    else $('.sa-bb-layout').before($('<div class="sa-bb-toggle-row"></div>').append($link));
    $link.toggleClass('is-active', !$('#sa-bb-panel').prop('hidden'))
      .attr('aria-expanded', $('#sa-bb-panel').prop('hidden') ? 'false' : 'true');
  }

  function setOpen(open) {
    var $panel = $('#sa-bb-panel');
    $panel.prop('hidden', !open);
    $('#sa-bb-toggle').toggleClass('is-active', open).attr('aria-expanded', open ? 'true' : 'false');
    writeOpen(open);
    if (open && !$panel.data('loaded')) {
      $panel.data('loaded', true);
      load(true);
    }
    try { w.dispatchEvent(new Event('resize')); } catch (e) { /* ignore */ }
    scheduleSticky();
  }

  // ----- list --------------------------------------------------------------------------------------------

  function load(reset) {
    if (reset) state.offset = 0;
    var seq = ++state.seq;
    state.loading = true;
    var $list = $('#sa-bb-list');
    if (reset) $list.addClass('is-loading');
    else $list.append('<p class="sa-bb-panel__loading">' + esc(t('loading')) + '</p>');
    $.getJSON(cfg.listUrl, {
      source: state.source,
      q: state.q,
      tracker_id: state.trackerId,
      offset: state.offset,
      target_version_id: cfg.target ? cfg.target.id : ''
    }).done(function (data) {
      if (seq !== state.seq) return;
      renderSources(data.sources || []);
      if (reset) $list.empty();
      (data.issues || []).forEach(function (issue) { $list.append(renderItem(issue)); });
      if (!$list.children('.sa-bb-item').length) {
        $list.html('<p class="sa-bb-panel__empty">' + esc(t('empty')) + '</p>');
      }
      state.offset = data.next_offset || 0;
      state.hasMore = !!data.has_more;
      makeDraggable($list.find('.sa-bb-item:not(.ui-draggable)'));
    }).always(function () {
      if (seq !== state.seq) return;
      state.loading = false;
      $list.removeClass('is-loading').children('.sa-bb-panel__loading').remove();
      maybeLoadMore();
      scheduleSticky();
    });
  }

  // Infinite scroll: the next page loads when the list is scrolled near its end (or does not fill the panel).
  function maybeLoadMore() {
    var list = document.getElementById('sa-bb-list');
    if (!list || state.loading || !state.hasMore || $('#sa-bb-panel').prop('hidden')) return;
    if (list.scrollTop + list.clientHeight >= list.scrollHeight - 60) load(false);
  }

  // The panel follows the viewport while the board is scrolled. CSS sticky does not apply here: #content
  // is a scroll container (overflow: auto) that does not scroll vertically.
  var stickyFrame = null;
  function syncSticky() {
    stickyFrame = null;
    var panel = document.getElementById('sa-bb-panel');
    if (!panel || panel.hidden) return;
    var layout = panel.parentElement;
    if (w.getComputedStyle(layout).flexDirection === 'column') {
      panel.style.transform = '';
      panel.style.maxHeight = '';
      return;
    }
    // Header pinned 8px below the viewport top; the panel ends with the board (shrinking near the board's
    // end rather than sliding up) and is never taller than the viewport.
    var gap = 8;
    var minHeight = 240;
    var board = layout.querySelector('.agile-board') || layout;
    var layoutTop = layout.getBoundingClientRect().top;
    var boardBottom = board.getBoundingClientRect().bottom;
    var top = Math.max(layoutTop, gap);
    var height = Math.min(w.innerHeight - gap * 2, boardBottom - top);
    if (height < minHeight) {
      height = minHeight;
      top = Math.max(layoutTop, boardBottom - minHeight);
    }
    panel.style.maxHeight = Math.floor(height) + 'px';
    var shift = top - layoutTop;
    panel.style.transform = shift ? 'translateY(' + Math.round(shift) + 'px)' : '';
  }

  function scheduleSticky() {
    if (stickyFrame) return;
    stickyFrame = (w.requestAnimationFrame || function (fn) { return setTimeout(fn, 16); })(syncSticky);
  }

  function renderSources(sources) {
    var $sel = $('#sa-bb-source');
    if ($sel.data('filled')) return;
    $sel.data('filled', true);
    $sel.html(sources.map(function (s) {
      return '<option value="' + esc(s.value) + '">' + esc(s.label) + '</option>';
    }).join(''));
    $sel.val(state.source);
  }

  // "Size: Total 5 · BE 3 · FE 2" (+ "This sprint: …" for a ticket on a sprint), shown on hover.
  function spTip(issue) {
    function line(title, total, parts) {
      var bits = [];
      if (total != null) bits.push(t('total') + ' ' + total);
      ['be', 'fe', 'qa'].forEach(function (p) {
        if (parts && parts[p] != null) bits.push(p.toUpperCase() + ' ' + parts[p]);
      });
      return bits.length ? title + ': ' + bits.join(' · ') : '';
    }
    var sprint = issue.sprint_sp || {};
    return [
      line(t('sizeGroup'), issue.sp, issue.size),
      line(t('sprintGroup'), sprint.total, sprint)
    ].filter(Boolean).join('\n');
  }

  function renderBadges(issue) {
    var out = [];
    var tip = spTip(issue);
    var hasSize = issue.sp != null || Object.keys(issue.size || {}).length;
    if (hasSize || tip) {
      out.push('<span class="sa-bb-badge sa-bb-badge--sp" data-sa-tip="' + esc(tip) + '">' +
        esc(issue.sp != null ? issue.sp : '—') + ' SP</span>');
    }
    [['done_be', 'BE'], ['done_fe', 'FE']].forEach(function (pair) {
      var sprint = issue[pair[0]];
      if (!sprint) return;
      out.push('<span class="sa-bb-badge sa-bb-badge--done" title="' +
        esc(t('doneIn').replace('__PART__', pair[1]).replace('__SPRINT__', sprint)) + '">&#10003; ' +
        esc(pair[1]) + '</span>');
    });
    var sub = issue.subtasks;
    if (sub && sub.total) {
      out.push('<span class="sa-bb-badge sa-bb-badge--sub" title="' + esc(t('subtasks')) + '">' +
        esc(t('subtaskCount').replace('__DONE__', sub.done).replace('__TOTAL__', sub.total)) + '</span>');
    }
    return out.length ? '<div class="sa-bb-item__badges">' + out.join('') + '</div>' : '';
  }

  function renderItem(issue) {
    var meta = [issue.status, issue.assignee].filter(Boolean).map(esc).join(' · ');
    var $item = $(
      '<div class="sa-bb-item" data-id="' + esc(issue.id) + '">' +
        '<div class="sa-bb-item__top">' +
          '<span class="sa-bb-item__tracker">' + esc(issue.tracker) + '</span>' +
          '<a class="sa-bb-item__id" href="' + esc(issue.url) + '" target="_blank" rel="noopener">#' + esc(issue.id) + '</a>' +
          (issue.priority
            ? '<span class="sanan-agile-priority sa-bb-item__priority" title="' + esc(issue.priority) + '">' +
                '<span class="priority priority-' + esc(issue.priority_key || 'default') + '"></span>' +
                esc(issue.priority) + '</span>'
            : '') +
        '</div>' +
        '<div class="sa-bb-item__subject">' + esc(issue.subject) + '</div>' +
        (meta ? '<div class="sa-bb-item__meta">' + meta + '</div>' : '') +
        renderBadges(issue) +
      '</div>'
    );
    $item.data('issue', issue);
    paintTracker($item, issue.tracker);
    return $item;
  }

  // Same tracker colours as the board cards (Settings → Agile board → card colour by tracker).
  function paintTracker($item, trackerName) {
    var map = w.SANAN_TRACKER_COLORS || {};
    var color = map[trackerName];
    if (!color) return;
    var mode = String(w.SANAN_TRACKER_COLOR_MODE || 'body').toLowerCase();
    if (mode === 'border') {
      $item.addClass('sa-bb-item--border').css('border-left-color', color);
    } else {
      $item.addClass('sa-bb-item--body').css('background-color', color);
    }
  }

  // Hover tooltip (fixed to the viewport, so the panel's scrolling list does not clip it).
  function bindTips() {
    if (bindTips.done) return;
    bindTips.done = true;
    var $tip = null;
    $(document).on('mouseenter', '#sa-bb-panel [data-sa-tip]', function () {
      var text = this.getAttribute('data-sa-tip');
      if (!text) return;
      if (!$tip) $tip = $('<div class="sa-bb-tip" role="tooltip"></div>').appendTo('body');
      $tip.text(text).show();
      var r = this.getBoundingClientRect();
      var top = r.bottom + 6;
      if (top + $tip.outerHeight() > w.innerHeight - 8) top = r.top - $tip.outerHeight() - 6;
      $tip.css({ left: Math.max(8, Math.min(r.left, w.innerWidth - $tip.outerWidth() - 8)), top: top });
    }).on('mouseleave dragstart', '#sa-bb-panel [data-sa-tip]', function () {
      if ($tip) $tip.hide();
    });
  }

  // ----- drag & drop -------------------------------------------------------------------------------------

  function makeDraggable($items) {
    if (!cfg.target || !$.fn.draggable) {
      $items.addClass('is-disabled');
      return;
    }
    $items.draggable({
      helper: 'clone',
      appendTo: 'body',
      zIndex: 10000,
      revert: 'invalid',
      revertDuration: 150,
      cursor: 'grabbing',
      cancel: 'a',
      start: function (e, ui) {
        ui.helper.addClass('sa-bb-item--helper').width($(this).width());
        $('body').addClass('sa-bb-dragging');
      },
      stop: function () { $('body').removeClass('sa-bb-dragging'); }
    });
  }

  function bindDroppable() {
    if (!cfg.target || !$.fn.droppable) return;
    $('table.issues-board td.issue-status-col[data-id]').each(function () {
      var $col = $(this);
      if (!$col.attr('data-id') || $col.data('saBbDrop')) return;
      $col.data('saBbDrop', true);
      $col.droppable({
        accept: '.sa-bb-item',
        tolerance: 'pointer',
        hoverClass: 'sa-bb-drop-hover',
        drop: function (e, ui) { onDrop(ui.draggable, $col); }
      });
    });
  }

  function columnName(statusId) {
    var $th = $('table.issues-board thead th[data-column-id="' + statusId + '"]').first();
    var text = $th.clone().children('span.count, span.hours').remove().end().text();
    text = $.trim(text).replace(/\s*\(\s*\d*\s*\)\s*$/, ''); // drop the "(count)" suffix
    return text || String(statusId);
  }

  function onDrop($item, $col) {
    var issue = $item.data('issue');
    var statusId = $col.attr('data-id');
    if (!issue || !statusId) return;
    var parts = (cfg.spParts || []).filter(function (p) { return (issue.sp_parts || []).indexOf(p) !== -1; });
    if (!parts.length) {
      pull(issue, statusId, {}, $item, $col, null);
      return;
    }
    openDialog(issue, statusId, parts, $item, $col);
  }

  // The board's card drag (redmine_agile sortable) moves the card itself inside the horizontally scrolling
  // board, and jQuery UI then offsets it by the page scroll. A clone appended to <body> follows the pointer
  // exactly (also over the panel); the board's own drop handling still works on ui.item.
  function fixBoardDragHelper() {
    var $cols = $('table.issues-board:not(.sticky) td.issue-status-col.ui-sortable');
    if (!$cols.length || $cols.first().data('saBbHelper')) return;
    $cols.data('saBbHelper', true).sortable('option', {
      helper: 'clone',
      appendTo: 'body',
      zIndex: 10000,
      start: chain($cols.sortable('option', 'start'), function (e, ui) {
        ui.helper.addClass('sa-bb-card-helper').width(ui.item.outerWidth());
        ui.item.show().addClass('sa-bb-card-source');
      }),
      stop: chain(function (e, ui) { ui.item.removeClass('sa-bb-card-source'); }, $cols.sortable('option', 'stop'))
    });
  }

  function chain(first, second) {
    return function () {
      if (typeof first === 'function') first.apply(this, arguments);
      if (typeof second === 'function') second.apply(this, arguments);
    };
  }

  // A board card dropped on the panel goes back to the panel's source (Product Backlog / that sprint).
  function bindPanelDrop() {
    var $panel = $('#sa-bb-panel');
    if (!$.fn.droppable || $panel.data('ui-droppable')) return;
    $panel.droppable({
      accept: '.issue-card',
      tolerance: 'pointer',
      activeClass: 'sa-bb-panel--accept',
      hoverClass: 'sa-bb-panel--hover',
      activate: function () {
        var name = $('#sa-bb-source option:selected').text() || t('title');
        $panel.find('.sa-bb-panel__drop span').text(t('dropHere').replace('__NAME__', name));
      },
      drop: function (e, ui) { onCardDrop(ui.draggable); }
    });
  }

  function onCardDrop($card) {
    var issueId = $card.attr('data-id') || $card.data('id');
    if (!issueId) return;
    // Put the board's sortable placeholder back where the card started, so the board's own drop handler
    // sees no change (no status update) and the card stays put until the move succeeds.
    var inst = $.ui && $.ui.ddmanager && $.ui.ddmanager.current;
    if (inst && inst.placeholder && inst.currentItem) inst.currentItem.after(inst.placeholder);
    setTimeout(function () { push(issueId, $card); }, 0);
  }

  function push(issueId, $card) {
    $('#sa-bb-error').prop('hidden', true);
    $card.addClass('is-pulling');
    $.ajax({
      url: cfg.pushUrl,
      type: 'POST',
      dataType: 'json',
      headers: { 'X-CSRF-Token': csrf() },
      data: { issue_id: issueId, source: state.source }
    }).done(function () {
      $('.issue-card[data-id="' + issueId + '"]').remove();
      var U = w.SananAgileUtil;
      if (U && U.syncBoardColumnCounts) U.syncBoardColumnCounts();
      load(true);
    }).fail(function (xhr) {
      $card.removeClass('is-pulling');
      var body = xhr.responseJSON || {};
      var messages = body.errors && body.errors.length ? body.errors : [t('pushFailed')];
      $('#sa-bb-error').text(messages.join('\n')).prop('hidden', false);
    });
  }

  // ----- SP dialog ---------------------------------------------------------------------------------------

  function openDialog(issue, statusId, parts, $item, $col) {
    closeDialog();
    var opts = '<option value=""></option>' + (cfg.spOptions || []).map(function (v) {
      return '<option value="' + esc(v) + '">' + esc(v) + '</option>';
    }).join('');
    var fields = parts.map(function (p) {
      var hint = issue.size && issue.size[p] != null
        ? '<span class="sa-bb-dialog__size">' + esc(t('size')) + ' ' + esc(issue.size[p]) + '</span>' : '';
      return '<label class="sa-bb-dialog__field"><span>' + esc(t(p)) + hint + '</span>' +
        '<select name="' + esc(p) + '">' + opts + '</select></label>';
    }).join('');
    var into = esc(t('modalInto'))
      .replace('__SPRINT__', '<strong>' + esc(cfg.target.name) + '</strong>')
      .replace('__STATUS__', '<strong>' + esc(columnName(statusId)) + '</strong>');
    var $dlg = $(
      '<div class="sa-bb-overlay" role="dialog" aria-modal="true">' +
        '<form class="sa-bb-dialog">' +
          '<h3 class="sa-bb-dialog__title">' + esc(t('modalTitle')).replace('__ID__', esc(issue.id)) + '</h3>' +
          '<p class="sa-bb-dialog__subject">' + esc(issue.subject) + '</p>' +
          '<p class="sa-bb-dialog__into">' + into + '</p>' +
          '<div class="sa-bb-dialog__fields">' + fields + '</div>' +
          '<p class="sa-bb-dialog__hint">' + esc(t('modalSpHint')) + '</p>' +
          '<p class="sa-bb-dialog__error" hidden></p>' +
          '<div class="sa-bb-dialog__actions">' +
            '<button type="button" class="sa-bb-dialog__cancel">' + esc(t('cancel')) + '</button>' +
            '<button type="submit" class="sa-bb-dialog__submit">' + esc(t('submit')) + '</button>' +
          '</div>' +
        '</form>' +
      '</div>'
    );
    $('body').append($dlg);
    $dlg.find('select').first().trigger('focus');
    $dlg.on('click', function (e) { if (e.target === $dlg[0]) closeDialog(); });
    $dlg.find('.sa-bb-dialog__cancel').on('click', closeDialog);
    $dlg.find('form').on('submit', function (e) {
      e.preventDefault();
      var sp = {};
      $dlg.find('select').each(function () { sp[this.name] = this.value; });
      // One part is enough to commit; QA alone is not (it needs BE or FE).
      var hasDevPart = parts.indexOf('be') !== -1 || parts.indexOf('fe') !== -1;
      if (hasDevPart && sp.qa && !sp.be && !sp.fe) {
        showError($dlg, [t('qaNeedsDev')]);
        $dlg.find('select[name="be"], select[name="fe"]').first().trigger('focus');
        return;
      }
      pull(issue, statusId, sp, $item, $col, $dlg);
    });
    $(document).on('keydown.saBbDialog', function (e) { if (e.key === 'Escape') closeDialog(); });
  }

  function closeDialog() {
    $('.sa-bb-overlay').remove();
    $(document).off('keydown.saBbDialog');
  }

  function showError($dlg, messages) {
    var text = (messages && messages.length ? messages : [t('failed')]).join('\n');
    if ($dlg) {
      $dlg.find('.sa-bb-dialog__error').text(text).prop('hidden', false);
      $dlg.find('.sa-bb-dialog__submit').prop('disabled', false);
    } else {
      w.alert(text);
    }
  }

  // ----- pull --------------------------------------------------------------------------------------------

  function pull(issue, statusId, sp, $item, $col, $dlg) {
    if ($dlg) $dlg.find('.sa-bb-dialog__submit').prop('disabled', true);
    $item.addClass('is-pulling');
    $.ajax({
      url: cfg.pullUrl,
      type: 'POST',
      dataType: 'json',
      headers: { 'X-CSRF-Token': csrf() },
      data: { issue_id: issue.id, version_id: cfg.target.id, status_id: statusId, sp: sp }
    }).done(function (data) {
      closeDialog();
      $item.remove();
      if (!$('#sa-bb-list .sa-bb-item').length) load(true);
      // Card tags ("Commit") read these maps when the new card is decorated.
      if (w.SA_ISSUE_SPRINT) w.SA_ISSUE_SPRINT[issue.id] = String(cfg.target.id);
      if (w.SA_COMMITTED) w.SA_COMMITTED[issue.id] = !!(data && data.committed);
      if (w.SA_ISSUE_TRACKER) w.SA_ISSUE_TRACKER[issue.id] = issue.tracker_id;
      insertCard(issue.id, statusId, $col);
    }).fail(function (xhr) {
      $item.removeClass('is-pulling');
      var body = xhr.responseJSON || {};
      showError($dlg, body.errors);
    });
  }

  // The board's own update endpoint renders the card with the board's columns and query.
  function insertCard(issueId, statusId, $col) {
    if (!cfg.cardUrl) { w.location.reload(); return; }
    $.ajax({
      url: cfg.cardUrl,
      type: 'PUT',
      headers: { 'X-CSRF-Token': csrf() },
      data: { id: issueId, issue: { status_id: statusId } }
    }).done(function (html) {
      var $card = $($.parseHTML($.trim(html), document, true)).filter('.issue-card');
      if (!$card.length) { w.location.reload(); return; }
      var $first = $col.children('.issue-card').first();
      if ($first.length) $first.before($card); else $col.prepend($card);
      $col.removeClass('empty');
      $card.addClass('sa-bb-card--new');
      setTimeout(function () { $card.removeClass('sa-bb-card--new'); }, 1600);
      var U = w.SananAgileUtil;
      if (U && U.boot) U.boot();
      if (U && U.syncBoardColumnCounts) U.syncBoardColumnCounts();
    }).fail(function () { w.location.reload(); });
  }

  // ----- boot --------------------------------------------------------------------------------------------

  function bindControls() {
    var $panel = $('#sa-bb-panel');
    if ($panel.data('bound')) return;
    $panel.data('bound', true);
    $panel.on('click', '.sa-bb-panel__close', function () { setOpen(false); });
    $panel.on('change', '#sa-bb-source', function () { state.source = this.value || 'backlog'; load(true); });
    $panel.on('change', '#sa-bb-tracker', function () { state.trackerId = this.value || ''; load(true); });
    $panel.on('input', '#sa-bb-search', debounce(function (e) { state.q = e.target.value || ''; load(true); }, 300));
    $('#sa-bb-list').on('scroll', debounce(maybeLoadMore, 80));
    $(w).off('scroll.saBb resize.saBb').on('scroll.saBb resize.saBb', scheduleSticky);
    $(document).off('click.saBbToggle').on('click.saBbToggle', '#sa-bb-toggle', function (e) {
      e.preventDefault();
      setOpen($('#sa-bb-panel').prop('hidden'));
    });
  }

  function boot() {
    cfg = w.SA_BOARD_BACKLOG;
    if (!cfg || !cfg.listUrl) return;
    if (!ensureLayout()) return;
    bindControls();
    bindTips();
    bindDroppable();
    bindPanelDrop();
    setOpen(readOpen());
    $(function () { ensureToggle(); fixBoardDragHelper(); });
  }

  w.SananBoardBacklog = { boot: boot };
  $(function () {
    boot();
    fixBoardDragHelper(); // every board user, with or without the panel
  });
})(window, window.jQuery);
