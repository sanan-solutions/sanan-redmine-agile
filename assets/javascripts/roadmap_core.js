(function ($) {
  'use strict';

  // Product Roadmap — shared namespace, state and data helpers.
  // Board data: { year, current_quarter, statuses, products: [{ id, name, quarters, unplanned, capacity, urls, ... }] }.
  // The project page is the single-product case of the same board.
  // Load order: core, board, team, detail, actions, roadmap (boot).
  var R = window.SananRoadmap = window.SananRoadmap || {};

  R.HEALTH_COLORS = { on_track: '#22c55e', at_risk: '#f59e0b', off_track: '#ef4444' };
  R.QUARTERS = [1, 2, 3, 4];
  // Shared mutable state, set on boot: R.$root, R.data, R.t (i18n), R.state.

  R.csrfToken = function () {
    return $('meta[name="csrf-token"]').attr('content') ||
      $('input[name="authenticity_token"]').val();
  };

  R.esc = function (s) {
    return String(s === null || s === undefined ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  };

  R.fmt = function (str, vars) {
    return String(str || '').replace(/%\{(\w+)\}/g, function (m, k) { return vars[k] === undefined ? m : vars[k]; });
  };

  R.fmtSp = function (n) {
    n = Number(n) || 0;
    return Math.round(n * 10) / 10;
  };

  R.readJson = function (id) {
    try { return JSON.parse($('#' + id).text() || '{}'); } catch (e) { return {}; }
  };

  R.isPortfolio = function () { return R.$root.hasClass('is-portfolio'); };

  R.issueUrl = function (id) { return R.$root.attr('data-issue-url') + '/' + id; };

  R.filtersActive = function () { return !!(R.state.status || R.state.health || R.state.q || R.state.owner); };

  R.issueLink = function (id, label) {
    return '<a href="' + R.esc(R.issueUrl(id)) + '" class="rm-issue-link" data-issue-id="' + id + '">' + label + '</a>';
  };

  R.newIssueUrl = function (product, params) {
    var q = Object.keys(params).filter(function (k) { return params[k]; }).map(function (k) {
      return encodeURIComponent('issue[' + k + ']') + '=' + encodeURIComponent(params[k]);
    }).join('&');
    return product.urls.new_issue + (q ? '?' + q : '');
  };

  R.request = function (type, url, payload) {
    return $.ajax({
      url: url,
      type: type,
      dataType: 'json',
      headers: { 'X-CSRF-Token': R.csrfToken(), 'X-Requested-With': 'XMLHttpRequest' },
      data: payload
    }).fail(function (xhr) {
      var msg = xhr.responseJSON && xhr.responseJSON.error ? xhr.responseJSON.error : xhr.status;
      window.alert((R.t.error || 'Request failed') + ': ' + msg);
    });
  };

  R.setData = function (fresh) {
    R.data = fresh || {};
    R.data.products = R.data.products || [];
    R.data.products.forEach(function (p) {
      p.quarters = p.quarters || {};
      R.QUARTERS.forEach(function (q) { p.quarters[String(q)] = p.quarters[String(q)] || []; });
      p.unplanned = p.unplanned || [];
    });
  };

  R.productById = function (id) {
    id = Number(id);
    for (var i = 0; i < R.data.products.length; i++) if (R.data.products[i].id === id) return R.data.products[i];
    return null;
  };

  R.listFor = function (product, quarter) {
    return Number(quarter) === 0 ? product.unplanned : product.quarters[String(quarter)];
  };

  R.plannedEpics = function (product) {
    var products = product ? [product] : R.data.products;
    var out = [];
    products.forEach(function (p) {
      R.QUARTERS.forEach(function (q) { out = out.concat(p.quarters[String(q)] || []); });
    });
    return out;
  };

  R.productOf = function (epic) {
    var found = epic && R.findEpic(epic.id);
    return found ? found.product : null;
  };

  R.findEpic = function (id) {
    id = Number(id);
    for (var p = 0; p < R.data.products.length; p++) {
      var product = R.data.products[p];
      var lists = [product.unplanned].concat(R.QUARTERS.map(function (q) { return product.quarters[String(q)]; }));
      for (var i = 0; i < lists.length; i++) {
        for (var j = 0; j < lists[i].length; j++) {
          if (lists[i][j].id === id) return { epic: lists[i][j], list: lists[i], index: j, product: product };
        }
      }
    }
    return null;
  };

  R.epicVisible = function (epic) {
    if (R.state.health && epic.health !== R.state.health) return false;
    if (R.state.owner && (epic.owner || '') !== R.state.owner) return false;
    if (R.state.q) {
      var q = R.state.q.toLowerCase().replace(/^#/, '');
      if (String(epic.id) !== q && String(epic.subject).toLowerCase().indexOf(q) === -1) return false;
    }
    if (R.state.status) {
      var sid = Number(R.state.status);
      return epic.status_id === sid || epic.stories.some(function (s) { return s.status_id === sid; });
    }
    return true;
  };

  R.dot = function (color, extra) {
    return '<span class="rm-dot' + (extra ? ' ' + extra : '') + '" style="background:' + R.esc(color) + '"></span>';
  };

  R.healthLabel = function (h) { return (R.t.health && R.t.health[h]) || h; };

  R.quarterLabel = function (year, quarter) { return 'Q' + quarter + (Number(year) === Number(R.data.year) ? '' : '/' + year); };

  // Ready to release (done / sp_done) and development done (dev / sp_dev), by Size else by count.
  R.progressOf = function (epics) {
    var stories = 0, done = 0, dev = 0, spTotal = 0, spDone = 0, spDev = 0;
    epics.forEach(function (e) {
      stories += e.story_count;
      done += e.done_count;
      dev += e.dev_count || 0;
      spTotal += Number(e.sp_total) || 0;
      spDone += Number(e.sp_done) || 0;
      spDev += Number(e.sp_dev) || 0;
    });
    function pctOf(sp, n) {
      return spTotal > 0 ? Math.round(sp / spTotal * 100) : (stories > 0 ? Math.round(n / stories * 100) : 0);
    }
    return { stories: stories, done: done, dev: dev, spTotal: spTotal, spDone: spDone, spDev: spDev,
             pct: pctOf(spDone, done), devPct: pctOf(spDev, dev) };
  };

  // Two-colour bar: ready to release (dark) over development done (light). tipHtml: R.progressTipHtml().
  R.splitBar = function (ready, dev, tipHtml, extraClass) {
    ready = Math.max(0, Math.min(100, Number(ready) || 0));
    dev = Math.max(ready, Math.min(100, Number(dev) || 0));
    return '<div class="rm-bar rm-bar--split' + (extraClass ? ' ' + extraClass : '') + '"' +
      (tipHtml ? ' data-rm-tip="' + R.esc(tipHtml) + '"' : '') + '>' +
      '<b style="width:' + dev + '%"></b><i style="width:' + ready + '%"></i></div>';
  };

  // Hover explanation of a progress bar: what each colour means, its share and SP, what is left out.
  // o: R.progressOf / R.epicProgress; opts: { excluded: n, forecast: R.forecast() }.
  R.progressTipHtml = function (o, opts) {
    opts = opts || {};
    var bySp = Number(o.spTotal) > 0;
    var total = bySp ? Number(o.spTotal) : Number(o.stories) || 0;
    var ready = bySp ? Number(o.spDone) : Number(o.done) || 0;
    var dev = bySp ? Number(o.spDev) : Number(o.dev) || 0;
    function amount(n) { return bySp ? R.fmtSp(n) + ' ' + R.t.sp : n + ' ' + R.t.stories; }
    function pct(n) { return total > 0 ? Math.round(n / total * 100) : 0; }
    function row(cls, label, hint, n) {
      return '<div class="rm-tip__row"><span class="rm-tip__sw rm-tip__sw--' + cls + '"></span>' +
        '<span class="rm-tip__label"><b>' + R.esc(label) + '</b><small>' + R.esc(hint) + '</small></span>' +
        '<span class="rm-tip__val"><b>' + pct(n) + '%</b><small>' + R.esc(amount(n)) + '</small></span></div>';
    }
    var html = '<div class="rm-tip__title">' + R.esc(R.fmt(R.t.tip_title, { total: amount(total) })) + '</div>' +
      row('ready', R.t.ready, R.t.tip_ready, ready) +
      row('dev', R.t.tip_dev_only, R.t.tip_dev, Math.max(dev - ready, 0)) +
      row('rest', R.t.tip_rest, R.t.tip_rest_hint, Math.max(total - dev, 0));
    if (opts.excluded) html += '<div class="rm-tip__note">' + R.esc(R.fmt(R.t.tip_excluded, { n: opts.excluded })) + '</div>';
    if (opts.forecast) html += '<div class="rm-tip__note">⏱ ' + R.esc(opts.forecast.text) + '<br><small>' + R.esc(opts.forecast.hint) + '</small></div>';
    if (!bySp) html += '<div class="rm-tip__note"><small>' + R.esc(R.t.tip_by_count) + '</small></div>';
    return html;
  };

  R.epicTipHtml = function (epic, product) {
    return R.progressTipHtml(R.epicProgress(epic), { excluded: epic.excluded_count, forecast: R.forecast(epic, product) });
  };

  // One floating tooltip for every [data-rm-tip] (bars, % labels): appended to <body>, so drawers and
  // scrolling lists do not clip it.
  R.bindTips = function () {
    if (R.bindTips.done) return;
    R.bindTips.done = true;
    var $tip = null;
    $(document).on('mouseenter', '.sanan-roadmap [data-rm-tip]', function () {
      var html = this.getAttribute('data-rm-tip');
      if (!html) return;
      if (!$tip) $tip = $('<div class="rm-tip" role="tooltip"></div>').appendTo('body');
      $tip.html(html).show();
      var r = this.getBoundingClientRect();
      var w = $tip.outerWidth(), h = $tip.outerHeight();
      var top = r.bottom + 8;
      if (top + h > window.innerHeight - 8) top = Math.max(8, r.top - h - 8);
      var left = Math.max(8, Math.min(r.left + r.width / 2 - w / 2, window.innerWidth - w - 8));
      $tip.css({ top: top, left: left });
    }).on('mouseleave', '.sanan-roadmap [data-rm-tip]', function () {
      if ($tip) $tip.hide();
    });
    $(window).on('scroll', function () { if ($tip) $tip.hide(); });
  };
  $(function () { R.bindTips(); });

  R.epicProgress = function (e) {
    return { stories: e.story_count, done: e.done_count, dev: e.dev_count || 0, spTotal: Number(e.sp_total) || 0,
             spDone: Number(e.sp_done) || 0, spDev: Number(e.sp_dev) || 0, pct: e.progress, devPct: e.dev_progress || e.progress };
  };

  // "~2 sprints · around 15/11": Size left until ready to release / the product's team velocity.
  R.forecast = function (epic, product) {
    var cap = product && product.capacity;
    var velocity = cap && Number(cap.velocity);
    var left = (Number(epic.sp_total) || 0) - (Number(epic.sp_done) || 0);
    if (!velocity || velocity <= 0 || left <= 0 || epic.closed) return null;
    var sprints = Math.ceil(left / velocity);
    var days = Number(cap.sprint_days) || 14;
    var date = new Date(Date.now() + sprints * days * 86400000);
    return {
      text: R.fmt(R.t.forecast, { sprints: sprints, date: date.toLocaleDateString(undefined, { day: '2-digit', month: '2-digit', year: 'numeric' }) }),
      hint: R.fmt(R.t.forecast_hint, { velocity: R.fmtSp(velocity), days: days })
    };
  };

  R.epicCount = function (n) {
    return R.fmt(n === 1 ? R.t.epic_count_one : R.t.epic_count_other, { n: n });
  };

  // Quarter of the shown year already over (relative to the server's today).
  R.isPastQuarter = function (q) {
    var today = String(R.data.today || '');
    if (!today) return false;
    var y = Number(today.slice(0, 4));
    var tq = Math.floor((Number(today.slice(5, 7)) - 1) / 3) + 1;
    return Number(R.data.year) * 4 + q < y * 4 + tq;
  };

  // ISO date (yyyy-mm-dd) → UTC ms; null when blank.
  R.parseDate = function (iso) {
    if (!iso) return null;
    var p = String(iso).split('-');
    return Date.UTC(Number(p[0]), Number(p[1]) - 1, Number(p[2]));
  };

  // "12 Oct" (the year only when it is not the shown one).
  R.fmtDate = function (iso) {
    if (!iso) return '';
    var p = String(iso).split('-');
    var month = (R.t.months || [])[Number(p[1])] || p[1];
    return Number(p[2]) + ' ' + month + (Number(p[0]) !== Number(R.data.year) ? ' ' + p[0] : '');
  };

  R.isOverdue = function (item) {
    return !item.closed && !!item.due_date && !!R.data.today && item.due_date < R.data.today;
  };

  // "📅 1 Oct → 30 Nov" of an Epic / Story; empty when it has neither date.
  R.dateRange = function (item) {
    if (!item.start_date && !item.due_date) return '';
    var late = R.isOverdue(item);
    var tip = R.t.start_date + ': ' + (item.start_date || '—') + '\n' + R.t.due_date + ': ' + (item.due_date || '—') +
      (late ? '\n' + R.t.tl_overdue : '');
    return '<span class="rm-dates' + (late ? ' is-overdue' : '') + '" title="' + R.esc(tip) + '">📅 ' +
      R.esc(R.fmtDate(item.start_date) || '?') + ' → ' + R.esc(R.fmtDate(item.due_date) || '?') + '</span>';
  };

  R.baselineFor = function (product, quarter) {
    return product.baselines ? (product.baselines[String(quarter)] || product.baselines[quarter]) : null;
  };
})(jQuery);
