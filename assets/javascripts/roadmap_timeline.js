(function ($) {
  'use strict';

  // Product Roadmap — Timeline view (Gantt-like): the Epics of the shown year as bars on a Jan–Dec scale,
  // each expandable into its Stories. A bar runs from the issue's start date to its due date; when a date is
  // missing, the planned quarter(s) fill in (dashed bar). Filters, selection and the drawer are the board's.
  var R = window.SananRoadmap = window.SananRoadmap || {};
  var DAY = 86400000;

  R.isTimeline = function () { return !!R.$root && R.$root.hasClass('is-timeline'); };

  function year() { return Number(R.data.year); }
  function yearStart() { return Date.UTC(year(), 0, 1); }
  function yearEnd() { return Date.UTC(year() + 1, 0, 1); }
  function quarterStart(y, q) { return Date.UTC(y, (q - 1) * 3, 1); }
  function quarterEnd(y, q) { return Date.UTC(y, q * 3, 1); } // exclusive

  // Position on the scale, in % of the year.
  function pos(t) {
    return Math.max(0, Math.min(100, (t - yearStart()) / (yearEnd() - yearStart()) * 100));
  }

  // [start, end) of an Epic / Story in UTC ms, and where it came from:
  // dated (start + due), partial (one date, the other from the planned quarter), planned (quarter only).
  R.tlRange = function (item) {
    var s = R.parseDate(item.start_date);
    var e = R.parseDate(item.due_date);
    var kind = s !== null && e !== null ? 'dated' : (s !== null || e !== null ? 'partial' : 'planned');
    var ps = item.quarter ? quarterStart(item.year, item.quarter) : null;
    var pe = item.quarter ? quarterEnd(item.end_year || item.year, item.end_quarter || item.quarter) : null;
    if (e !== null) e += DAY; // the due date is the last day
    if (s === null) s = ps !== null && (e === null || ps < e) ? ps : (e !== null ? e - DAY : null);
    if (e === null) e = pe !== null && pe > s ? pe : (s !== null ? s + DAY : null);
    if (s === null || e === null) return null;
    if (e <= s) e = s + DAY;
    return { start: s, end: e, kind: kind };
  };

  function overlapsYear(range) { return range && range.end > yearStart() && range.start < yearEnd(); }

  // Rows of one product: planned Epics of the year, unplanned ones with dates in it, Epics continuing from an
  // earlier year; sorted by start.
  function epicRows(product) {
    var seen = {};
    var rows = [];
    R.plannedEpics(product).filter(R.epicVisible).forEach(function (e) {
      seen[e.id] = true;
      rows.push({ epic: e, range: R.tlRange(e) });
    });
    (product.unplanned || []).filter(R.epicVisible).forEach(function (e) {
      var range = R.tlRange(e);
      if (range && range.kind !== 'planned' && overlapsYear(range)) rows.push({ epic: e, range: range, unplanned: true });
    });
    if (!R.filtersActive()) {
      R.QUARTERS.forEach(function (q) {
        ((product.continuations || {})[String(q)] || []).forEach(function (c) {
          if (seen[c.id] || c.in_data) return;
          seen[c.id] = true;
          rows.push({ ghost: c, range: R.tlRange(c) });
        });
      });
    }
    rows.sort(function (a, b) {
      var sa = a.range ? a.range.start : Infinity, sb = b.range ? b.range.start : Infinity;
      if (sa !== sb) return sa < sb ? -1 : 1;
      return (a.epic || a.ghost).id - (b.epic || b.ghost).id;
    });
    return rows;
  }

  function rangeTip(item, range) {
    var lines = [R.t.start_date + ': ' + (item.start_date || '—'), R.t.due_date + ': ' + (item.due_date || '—')];
    if (range && range.kind === 'planned') lines.push(R.t.tl_planned);
    if (range && range.kind === 'partial' && item.quarter) lines.push(R.t.tl_partial);
    if (R.isOverdue(item)) lines.push(R.t.tl_overdue);
    return lines.join('\n');
  }

  var CHEVRON = '<svg width="12" height="12" viewBox="0 0 12 12" aria-hidden="true"><path d="M4.5 2.5 8 6l-3.5 3.5" fill="none" ' +
    'stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>';

  // The bar plus its caption, which sits outside the bar: after it, or before it near the end of the year.
  // An item outside the year gets an edge marker; one without any date, a muted "no dates".
  // o: { ready, dev, health, caption, title, attrs, story }
  function bar(item, range, o) {
    if (!range) return '<span class="rm-tl__nodate">' + R.esc(R.t.tl_no_dates) + '</span>';
    var tip = R.esc((o.title ? o.title + '\n' : '') + rangeTip(item, range));
    if (range.end <= yearStart() || range.start >= yearEnd()) {
      var before = range.end <= yearStart();
      return '<span class="rm-tl__out rm-tl__out--' + (before ? 'left' : 'right') + '" title="' + tip + '"' + o.attrs + '>' +
        (before ? '‹ ' : '') + R.esc(R.fmtDate(item.start_date || item.due_date) || '') + (before ? '' : ' ›') + '</span>';
    }
    var left = pos(range.start);
    var right = pos(range.end);
    var late = R.isOverdue(item);
    var cls = 'rm-tl__bar rm-tl__bar--' + range.kind + (o.story ? ' rm-tl__bar--story' : '') +
      (item.closed ? ' is-closed' : '') + (late ? ' is-overdue' : '') +
      (range.start < yearStart() ? ' is-clip-left' : '') + (range.end > yearEnd() ? ' is-clip-right' : '');
    var ready = Math.max(0, Math.min(100, Number(o.ready) || 0));
    var dev = Math.max(ready, Math.min(100, Number(o.dev) || 0));
    var caption = (o.caption || '') + (late ? ' <span class="rm-tl__late">' + R.esc(R.t.tl_overdue) + '</span>' : '');
    var flip = right > 82 && left > 18; // no room after the bar: caption before it
    return '<span class="' + cls + '" style="left:' + left + '%;width:' + Math.max(right - left, 0.35) + '%;' +
        (o.health ? '--rm-tl-health:' + o.health : '') + '" title="' + tip + '"' + o.attrs + '>' +
        '<b style="width:' + dev + '%"></b><i style="width:' + ready + '%"></i>' +
      '</span>' +
      (caption ? '<span class="rm-tl__caption' + (flip ? ' is-before' : '') + '" style="' +
        (flip ? 'right:' + (100 - left) + '%' : 'left:' + right + '%') + '">' + caption + '</span>' : '');
  }

  function epicCaption(e) {
    return '<b>' + e.progress + '%</b>' +
      ((e.dev_progress || 0) > e.progress ? ' <span class="rm-tl__dev">· dev ' + e.dev_progress + '%</span>' : '');
  }

  function epicRow(row) {
    var e = row.epic;
    var open = !!R.state.tlOpen[e.id];
    var sid = R.state.status ? Number(R.state.status) : null;
    var stories = e.stories.filter(function (s) { return !sid || s.status_id === sid; });
    var caret = e.stories.length
      ? '<button type="button" class="rm-tl__caret' + (open ? ' is-open' : '') + '" data-rm-tl-toggle="' + e.id +
        '" aria-expanded="' + open + '" title="' + R.esc(R.t.stories) + '">' + CHEVRON + '</button>'
      : '<span class="rm-tl__caret rm-tl__caret--none"></span>';
    var html = '<div class="rm-tl__row rm-tl__row--epic' + (open ? ' is-open' : '') +
        (R.state.selected === e.id ? ' is-selected' : '') + (e.closed ? ' is-closed' : '') + '">' +
      '<div class="rm-tl__label">' + caret + R.dot(e.color) +
        '<div class="rm-tl__text">' +
          '<a href="#" class="rm-tl__name" data-rm-tl-select="' + e.id + '" title="' + R.esc('#' + e.id + ' ' + e.subject) + '">' +
            R.esc(e.subject) + '</a>' +
          '<div class="rm-tl__sub"><span>#' + e.id + '</span>' + (e.priority ? R.priorityControl(e) : '') +
            '<span>' + e.done_count + '/' + e.story_count + ' ' + R.esc(R.t.stories) + '</span>' +
            (row.unplanned ? '<span class="rm-tag">' + R.esc(R.t.unplanned) + '</span>' : '') + '</div>' +
        '</div>' +
      '</div>' +
      '<div class="rm-tl__track">' +
        bar(e, row.range, {
          ready: e.progress, dev: e.dev_progress, health: e.quarter ? R.HEALTH_COLORS[e.health] : null,
          caption: epicCaption(e), title: '#' + e.id + ' ' + e.subject, attrs: ' data-rm-tl-select="' + e.id + '"'
        }) +
      '</div>' +
    '</div>';
    if (!open) return html;
    return html + stories.map(function (s, i) { return storyRow(s, i === stories.length - 1); }).join('');
  }

  function storyRow(s, last) {
    var tip = s.tracker + ' #' + s.id + ' ' + s.subject + '\n' + s.status + ' · ' + (s.assignee || R.t.unassigned) +
      (s.sp !== null && s.sp !== undefined ? ' · ' + R.fmtSp(s.sp) + ' ' + R.t.sp : '');
    return '<div class="rm-tl__row rm-tl__row--story' + (last ? ' is-last' : '') + (s.closed ? ' is-closed' : '') +
        (s.excluded ? ' is-excluded' : '') + '">' +
      '<div class="rm-tl__label"><span class="rm-tl__tree" aria-hidden="true"></span>' + R.dot(s.color, 'rm-dot--sm') +
        '<a href="' + R.esc(R.issueUrl(s.id)) + '" class="rm-tl__name rm-issue-link" data-issue-id="' + s.id + '" title="' + R.esc(tip) + '">' +
          '<span class="rm-tl__id">#' + s.id + '</span> <span class="rm-tl__subj">' + R.esc(s.subject) + '</span></a>' +
        (s.sp !== null && s.sp !== undefined ? '<span class="rm-tl__aside">' + R.fmtSp(s.sp) + ' ' + R.esc(R.t.sp) + '</span>' : '') +
      '</div>' +
      '<div class="rm-tl__track">' +
        bar(s, R.tlRange(s), {
          story: true, ready: s.ready ? 100 : 0, dev: s.ready || s.dev_done ? 100 : s.progress,
          caption: s.assignee ? '<span class="rm-tl__who">' + R.esc(s.assignee) + '</span>' : '',
          title: tip, attrs: ' data-rm-tl-issue="' + s.id + '"'
        }) +
      '</div>' +
    '</div>';
  }

  function ghostRow(row) {
    var c = row.ghost;
    return '<div class="rm-tl__row rm-tl__row--epic rm-tl__row--ghost' + (c.closed ? ' is-closed' : '') + '">' +
      '<div class="rm-tl__label"><span class="rm-tl__caret rm-tl__caret--none"></span>' + R.dot(c.color) +
        '<div class="rm-tl__text">' +
          '<a href="' + R.esc(R.issueUrl(c.id)) + '" class="rm-tl__name rm-issue-link" data-issue-id="' + c.id + '">' + R.esc(c.subject) + '</a>' +
          '<div class="rm-tl__sub"><span>#' + c.id + '</span><span>' + R.esc(R.fmt(R.t.continues_from, { from: c.from })) + '</span></div>' +
        '</div>' +
      '</div>' +
      '<div class="rm-tl__track">' +
        bar(c, row.range, { ready: c.progress, dev: c.dev_progress, caption: '<b>' + c.progress + '%</b>',
          title: '#' + c.id + ' ' + c.subject, attrs: ' data-rm-tl-issue="' + c.id + '"' }) +
      '</div>' +
    '</div>';
  }

  function todayMs() {
    var t = R.parseDate(R.data.today);
    return t !== null && t >= yearStart() && t < yearEnd() ? t : null;
  }

  function scale() {
    var y = year();
    var months = R.t.months || [];
    var cq = Number(R.data.current_quarter) || 0;
    var today = todayMs();
    var thisMonth = today !== null ? new Date(today).getUTCMonth() : -1;
    var quarters = R.QUARTERS.map(function (q) {
      var l = pos(quarterStart(y, q)), r = pos(quarterEnd(y, q));
      return '<span class="rm-tl__q' + (q === cq ? ' is-current' : '') + '" style="left:' + l + '%;width:' + (r - l) + '%">Q' + q + '</span>';
    }).join('');
    var monthCells = '';
    for (var m = 0; m < 12; m++) {
      var l = pos(Date.UTC(y, m, 1)), r = pos(Date.UTC(y, m + 1, 1));
      monthCells += '<span class="rm-tl__m' + (m % 3 === 0 ? ' is-qstart' : '') + (m === thisMonth ? ' is-now' : '') +
        '" style="left:' + l + '%;width:' + (r - l) + '%">' + R.esc(months[m + 1] || String(m + 1)) + '</span>';
    }
    var marker = today !== null
      ? '<span class="rm-tl__nowmark" style="left:' + pos(today + DAY / 2) + '%" title="' + R.esc(R.t.tl_today + ' · ' + R.fmtDate(R.data.today)) + '"></span>'
      : '';
    return '<div class="rm-tl__scale"><div class="rm-tl__qrow">' + quarters + '</div><div class="rm-tl__mrow">' + monthCells + '</div>' + marker + '</div>';
  }

  // Current quarter band, month / quarter lines and today, drawn once behind the rows.
  function gridLines() {
    var y = year();
    var cq = Number(R.data.current_quarter) || 0;
    var html = '';
    if (cq) {
      var l = pos(quarterStart(y, cq));
      html += '<span class="rm-tl__band" style="left:' + l + '%;width:' + (pos(quarterEnd(y, cq)) - l) + '%"></span>';
    }
    for (var m = 1; m < 12; m++) {
      html += '<span class="rm-tl__line' + (m % 3 === 0 ? ' is-q' : '') + '" style="left:' + pos(Date.UTC(y, m, 1)) + '%"></span>';
    }
    var today = todayMs();
    if (today !== null) html += '<span class="rm-tl__today" style="left:' + pos(today + DAY / 2) + '%"></span>';
    return '<div class="rm-tl__grid" aria-hidden="true">' + html + '</div>';
  }

  R.renderTimeline = function () {
    var $el = $('#rm-timeline');
    if (!$el.length || !R.isTimeline()) return;
    R.state.tlOpen = R.state.tlOpen || {};
    var many = R.data.products.length > 1;
    var total = 0;
    var body = R.data.products.map(function (p) {
      var rows = epicRows(p);
      total += rows.length;
      var html = rows.map(function (row) { return row.ghost ? ghostRow(row) : epicRow(row); }).join('');
      if (!many) return html;
      return '<div class="rm-tl__product"><span class="rm-tl__pname">' + R.esc(p.name) + '</span>' +
          '<span class="rm-tl__pcount">' + R.esc(R.epicCount(rows.length)) + '</span></div>' +
        (html || '<div class="rm-tl__row rm-tl__row--empty"><div class="rm-tl__label">' + R.esc(R.t.no_epics) + '</div><div class="rm-tl__track"></div></div>');
    }).join('');
    var anyOpen = Object.keys(R.state.tlOpen).some(function (k) { return R.state.tlOpen[k]; });
    $el.html(
      '<div class="rm-tl">' +
        '<div class="rm-tl__head">' +
          '<div class="rm-tl__corner"><b>' + R.esc(R.t.tl_items) + '</b>' +
            '<button type="button" class="rm-linkbtn" data-rm-tl-all="' + (anyOpen ? '0' : '1') + '">' +
              R.esc(anyOpen ? R.t.tl_collapse_all : R.t.tl_expand_all) + '</button></div>' +
          scale() +
        '</div>' +
        '<div class="rm-tl__body">' + gridLines() + body + '</div>' +
        (total ? '' : '<div class="rm-empty rm-tl__empty">' + R.esc(R.t.tl_empty) + '</div>') +
        '<div class="rm-tl__legend">' +
          '<span><span class="rm-tl__swatch rm-tl__swatch--dated"></span>' + R.esc(R.t.tl_legend_dated) + '</span>' +
          '<span><span class="rm-tl__swatch rm-tl__swatch--planned"></span>' + R.esc(R.t.tl_legend_planned) + '</span>' +
          '<span><span class="rm-tl__swatch rm-tl__swatch--ready"></span>' + R.esc(R.t.ready) + '</span>' +
          '<span><span class="rm-tl__swatch rm-tl__swatch--dev"></span>' + R.esc(R.t.dev_done) + '</span>' +
          '<span><span class="rm-tl__swatch rm-tl__swatch--today"></span>' + R.esc(R.t.tl_today) + '</span>' +
        '</div>' +
      '</div>'
    );
  };

  function epicsWithStories() {
    var ids = [];
    R.data.products.forEach(function (p) {
      R.plannedEpics(p).concat(p.unplanned || []).forEach(function (e) { if (e.stories.length) ids.push(e.id); });
    });
    return ids;
  }

  $(document).on('click', '#sanan-roadmap [data-rm-tl-toggle]', function (e) {
    e.preventDefault();
    var id = Number($(this).attr('data-rm-tl-toggle'));
    R.state.tlOpen[id] = !R.state.tlOpen[id];
    R.renderTimeline();
  });

  $(document).on('click', '#sanan-roadmap [data-rm-tl-all]', function () {
    var open = $(this).attr('data-rm-tl-all') === '1';
    R.state.tlOpen = {};
    if (open) epicsWithStories().forEach(function (id) { R.state.tlOpen[id] = true; });
    R.renderTimeline();
  });

  // Epic name / bar: the board's selection (drawer with the Epic detail).
  $(document).on('click', '#sanan-roadmap [data-rm-tl-select]', function (e) {
    if ($(e.target).closest('[data-rm-priority]').length) return;
    e.preventDefault();
    var id = Number($(this).attr('data-rm-tl-select'));
    R.state.selected = R.state.selected === id ? null : id;
    R.state.review = null;
    R.renderTimeline();
    R.renderDetail();
  });

  // Story bar / Epic of an earlier year: the issue, in the global modal when available.
  $(document).on('click', '#sanan-roadmap [data-rm-tl-issue]', function (e) {
    var id = $(this).attr('data-rm-tl-issue');
    if (window.SANAN_globalModal && !e.metaKey && !e.ctrlKey) {
      R.state.pendingEpic = null;
      window.SANAN_globalModal.viewIssue(id);
    } else {
      window.open(R.issueUrl(id), '_blank');
    }
  });
})(jQuery);
