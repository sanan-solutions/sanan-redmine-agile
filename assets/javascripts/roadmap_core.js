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

  R.progressOf = function (epics) {
    var stories = 0, done = 0, spTotal = 0, spDone = 0;
    epics.forEach(function (e) {
      stories += e.story_count;
      done += e.done_count;
      spTotal += Number(e.sp_total) || 0;
      spDone += Number(e.sp_done) || 0;
    });
    var pct = spTotal > 0 ? Math.round(spDone / spTotal * 100) : (stories > 0 ? Math.round(done / stories * 100) : 0);
    return { stories: stories, done: done, spTotal: spTotal, spDone: spDone, pct: pct };
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

  R.baselineFor = function (product, quarter) {
    return product.baselines ? (product.baselines[String(quarter)] || product.baselines[quarter]) : null;
  };
})(jQuery);
