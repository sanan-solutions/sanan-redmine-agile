(function ($) {
  'use strict';

  // Product Roadmap — right-hand panel: Epic detail, baseline review.
  var R = window.SananRoadmap = window.SananRoadmap || {};

  R.planControls = function (epic) {
    var year = epic.year || R.data.year;
    var opts = '<option value="0"' + (epic.quarter ? '' : ' selected') + '>' + R.esc(R.t.unplanned) + '</option>';
    R.QUARTERS.forEach(function (q) {
      opts += '<option value="' + q + '"' + (epic.quarter === q ? ' selected' : '') + '>Q' + q + '</option>';
    });
    var health = '';
    if (epic.quarter) {
      health = '<select class="rm-select rm-select--sm" data-rm-health>' +
        Object.keys(R.HEALTH_COLORS).map(function (h) {
          return '<option value="' + h + '"' + (epic.health === h ? ' selected' : '') + '>' + R.esc(R.healthLabel(h)) + '</option>';
        }).join('') + '</select>';
    }
    var span = '';
    if (epic.quarter) {
      span = '<span class="rm-small">' + R.esc(R.t.span) + '</span><select class="rm-select rm-select--sm" data-rm-span>' +
        [1, 2, 3, 4].map(function (n) {
          return '<option value="' + n + '"' + ((epic.span || 1) === n ? ' selected' : '') + '>' + R.esc(R.fmt(R.t.span_n, { n: n })) + '</option>';
        }).join('') + '</select>';
    }
    // Two labelled rows: where/how long, then health.
    return '<div class="rm-plan rm-plan--grid">' +
      '<span class="rm-plan__label">' + R.esc(R.t.plan_quarter) + '</span>' +
      '<span class="rm-plan__fields">' +
        '<input type="number" class="rm-select rm-select--sm rm-year-input" data-rm-plan-year value="' + year + '" min="2000" max="2199">' +
        '<select class="rm-select rm-select--sm" data-rm-plan-quarter>' + opts + '</select>' +
        span +
      '</span>' +
      (health ? '<span class="rm-plan__label">' + R.esc(R.t.plan_health) + '</span><span class="rm-plan__fields">' + health + '</span>' : '') +
    '</div>';
  };

  R.reviewRow = function (r) {
    var inData = !!R.findEpic(r.id);
    var sp = r.state === 'added'
      ? R.fmtSp(r.sp_now) + ' SP'
      : R.fmtSp(r.sp_done) + '/' + R.fmtSp(r.sp_baseline) + ' SP' + (r.sp_now !== null && r.sp_now !== r.sp_baseline ? ' (' + R.esc(R.fmt(R.t.bl_now_sp, { n: R.fmtSp(r.sp_now) })) + ')' : '');
    return '<div class="rm-review__row">' +
      '<div class="rm-review__title">' +
        (inData ? '<a href="#" data-rm-select="' + r.id + '">#' + r.id + '</a> ' : '#' + r.id + ' ') + R.esc(r.subject) +
        (r.now_in && (r.state === 'slipped' || r.state === 'moved') ? ' <span class="rm-small">→ ' + R.esc(r.now_in) + '</span>' : '') +
      '</div>' +
      '<span class="rm-small">' + sp + '</span>' +
    '</div>';
  };

  R.renderReview = function () {
    var product = R.productById(R.state.review.productId);
    var b = product && R.baselineFor(product, R.state.review.quarter);
    if (!b) { R.state.review = null; return false; }
    var s = b.summary;
    var tiles = [
      [R.t.bl_committed, s.committed_epics + ' · ' + R.fmtSp(s.sp_committed) + ' SP'],
      [R.t.bl_sp_done, R.fmtSp(s.sp_done) + '/' + R.fmtSp(s.sp_committed) + ' SP'],
      [R.t.bl_state.done, s.counts.done],
      [R.t.bl_state.slipped, s.counts.slipped],
      [R.t.bl_state.dropped, s.counts.dropped],
      [R.t.bl_state.added, s.counts.added + (s.sp_added ? ' · ' + R.fmtSp(s.sp_added) + ' SP' : '')]
    ];
    var groups = ['done', 'in_progress', 'slipped', 'moved', 'dropped', 'added'].map(function (st) {
      var rows = b.epics.filter(function (r) { return r.state === st; });
      if (!rows.length) return '';
      return '<div class="rm-review__group rm-review__group--' + st + '">' +
        '<div class="rm-team__role">' + R.esc(R.t.bl_state[st]) + ' (' + rows.length + ')</div>' +
        rows.map(R.reviewRow).join('') +
      '</div>';
    }).join('');

    R.showDrawer('detail');
    $('#rm-detail-body').html(
      R.backLink() +
      '<div class="rm-detail__top">' +
        '<div class="rm-eyebrow">' + R.esc(R.t.bl_title) + (R.isPortfolio() ? ' · ' + R.esc(product.name) : '') + '</div>' +
        '<button type="button" class="rm-icon-btn" data-rm-close title="' + R.esc(R.t.close) + '" aria-label="' + R.esc(R.t.close) + '">&times;</button>' +
      '</div>' +
      '<h3 class="rm-detail__title">Q' + b.quarter + '/' + b.year + '</h3>' +
      '<div class="rm-sub">' + R.esc(R.fmt(R.t.bl_captured, { date: b.captured_at, user: b.captured_by || '—' })) + '</div>' +
      '<div class="rm-review__tiles">' + tiles.map(function (x) {
        return '<div class="rm-review__tile"><div class="rm-kpi__l">' + R.esc(x[0]) + '</div><div class="rm-review__v">' + R.esc(x[1]) + '</div></div>';
      }).join('') + '</div>' +
      (product.can_manage
        ? '<div class="rm-plan"><button type="button" class="rm-btn rm-btn--sm" data-rm-rebaseline>' + R.esc(R.t.bl_relock) + '</button>' +
          '<button type="button" class="rm-btn rm-btn--sm rm-btn--danger" data-rm-baseline-delete>' + R.esc(R.t.bl_delete) + '</button></div>'
        : '') +
      '<div class="rm-review">' + (groups || '<div class="rm-empty">' + R.esc(R.t.no_epics) + '</div>') + '</div>'
    );
    return true;
  };

  R.hintBox = function (epic, product) {
    var h = R.hintFor(epic);
    if (!h) return '';
    return '<div class="rm-hintbox rm-hintbox--' + h.health + '">' +
      '<div><b>' + R.esc(R.t.hint) + ': ' + R.esc(R.healthLabel(h.health)) + '</b>' +
        (h.reasons.length ? '<ul>' + h.reasons.map(function (r) { return '<li>' + R.esc(r) + '</li>'; }).join('') + '</ul>' : '') +
      '</div>' +
      (product.can_manage ? '<button type="button" class="rm-btn rm-btn--sm" data-rm-hint-apply="' + h.health + '">' + R.esc(R.t.hint_apply) + '</button>' : '') +
    '</div>';
  };

  R.depRow = function (d, product) {
    var where = d.quarter ? 'Q' + d.quarter + '/' + d.year + (d.end_quarter ? '→Q' + d.end_quarter + '/' + d.end_year : '') : R.t.unplanned;
    return '<li class="' + (d.conflict ? 'is-late' : '') + (d.closed ? ' is-closed' : '') + '">' +
      R.issueLink(d.id, '#' + d.id) + ' ' + R.esc(d.subject) +
      ' <span class="rm-small">· ' + R.esc(where) + (d.project_id !== product.id ? ' · ' + R.esc(d.project) : '') +
      ' · ' + R.esc((R.t.rel_types || {})[d.type] || d.type) + '</span>' +
      (d.conflict ? ' <b class="rm-dep-late">' + R.esc(R.t.deps_late) + '</b>' : '') +
    '</li>';
  };

  R.dependencies = function (epic, product) {
    var on = epic.depends_on || [], blocking = epic.blocking || [];
    if (!on.length && !blocking.length) return '';
    return '<div class="rm-detail__stories-head"><b>' + R.esc(R.t.deps_title) + '</b></div>' +
      (on.length ? '<div class="rm-small rm-mt-sm">' + R.esc(R.t.deps_on) + '</div><ul class="rm-deps">' +
        on.map(function (d) { return R.depRow(d, product); }).join('') + '</ul>' : '') +
      (blocking.length ? '<div class="rm-small rm-mt-sm">' + R.esc(R.t.deps_blocking) + '</div><ul class="rm-deps">' +
        blocking.map(function (d) { return R.depRow(d, product); }).join('') + '</ul>' : '');
  };

  R.moveHistory = function (epic) {
    var mv = epic.moves || {};
    if (!mv.history || !mv.history.length) return '';
    return '<div class="rm-detail__stories-head"><b>' + R.esc(R.t.history) + '</b>' +
        (mv.slipped ? '<span class="rm-tag rm-tag--slip">↷ ' + R.esc(R.fmt(R.t.slip_short, { n: mv.slips, origin: mv.origin || '?' })) + '</span>' : '') +
      '</div>' +
      '<ul class="rm-history">' + mv.history.slice().reverse().map(function (h) {
        return '<li><span class="rm-small">' + R.esc(h.on) + '</span> ' + R.esc(h.from || R.t.unplanned) + ' → <b>' + R.esc(h.to || R.t.unplanned) + '</b>' +
          (h.by ? ' <span class="rm-small">· ' + R.esc(h.by) + '</span>' : '') + '</li>';
      }).join('') + '</ul>';
  };

  // Drawer shows one of: baseline review, Epic detail, Unplanned backlog — or is closed.
  // Drawer starts right below the Redmine header (top menu, project header, main menu) and moves up
  // as the header scrolls away.
  R.syncDrawerTop = function () {
    var main = document.getElementById('main');
    var top = main ? Math.max(0, Math.round(main.getBoundingClientRect().top)) : 0;
    R.$root[0].style.setProperty('--rm-drawer-top', top + 'px');
  };

  R.showDrawer = function (mode) {
    var open = !!mode;
    if (open) R.syncDrawerTop();
    $('#rm-detail').prop('hidden', !open);
    $('#rm-backlog').prop('hidden', mode !== 'backlog');
    $('#rm-detail-body').prop('hidden', mode === 'backlog' || !open);
    R.$root.toggleClass('has-detail', open);
    R.$root.find('[data-rm-backlog]').toggleClass('is-active', mode === 'backlog');
  };

  // "← Unplanned" link back to the backlog when it was the entry point.
  R.backLink = function () {
    return R.state.backlog
      ? '<button type="button" class="rm-linkbtn rm-backlink" data-rm-back-backlog>← ' + R.esc(R.t.back_to_backlog) + '</button>'
      : '';
  };

  // Where a story stands for the Epic progress: ready to release / development done / left out.
  R.storyPhase = function (s) {
    if (s.excluded) return '<span class="rm-phase rm-phase--out">' + R.esc(R.t.phase_out) + '</span>';
    if (s.ready) return '<span class="rm-phase rm-phase--ready">' + R.esc(R.t.ready) + '</span>';
    if (s.dev_done) return '<span class="rm-phase rm-phase--dev">' + R.esc(R.t.dev_done) + '</span>';
    return '<b class="rm-pct">' + s.progress + '%</b>';
  };

  R.renderDetail = function () {
    if (R.state.review && R.renderReview()) {
      R.showDrawer('detail');
      return;
    }
    var found = R.state.selected ? R.findEpic(R.state.selected) : null;
    if (!found) {
      R.state.selected = null;
      $('#rm-detail-body').empty();
      R.showDrawer(R.state.backlog ? 'backlog' : null);
      return;
    }
    var epic = found.epic;
    var product = found.product;
    var pills = '<span class="rm-pill">' + R.dot(epic.color) + R.esc(epic.status) + '</span>';
    if (epic.quarter && !product.can_manage) {
      pills += '<span class="rm-pill">' + R.dot(R.HEALTH_COLORS[epic.health]) + R.esc(R.healthLabel(epic.health)) + '</span>';
    }
    var tip = R.esc(R.epicTipHtml(epic, product));
    pills += '<span class="rm-pill rm-pill--ready" data-rm-tip="' + tip + '">' + R.esc(R.t.ready) + ' <b>' + epic.progress + '%</b></span>';
    pills += '<span class="rm-pill rm-pill--dev" data-rm-tip="' + tip + '">' + R.esc(R.t.dev_done) + ' <b>' + (epic.dev_progress || epic.progress) + '%</b></span>';
    if (epic.sp_total) pills += '<span class="rm-pill">' + R.fmtSp(epic.sp_done) + '/' + R.fmtSp(epic.sp_total) + ' ' + R.esc(R.t.sp) + '</span>';
    var forecast = R.forecast(epic, product);
    if (forecast) pills += '<span class="rm-pill" title="' + R.esc(forecast.hint) + '">⏱ ' + R.esc(forecast.text) + '</span>';
    (epic.releases || []).forEach(function (r) {
      pills += '<span class="rm-pill rm-rel--' + R.esc(r.state) + '" title="' + R.esc((R.t.rel_state || {})[r.state] || r.state) + '">🚀 ' + R.esc(r.name) + '</span>';
    });

    var sid = R.state.status ? Number(R.state.status) : null;
    var rows = epic.stories.filter(function (s) { return !sid || s.status_id === sid; }).map(function (s, i) {
      return '<div class="rm-story' + (s.closed ? ' is-closed' : '') + '">' +
        '<div class="rm-story__head">' +
          '<div class="rm-story__title"><span class="rm-small rm-idx">' + (i + 1) + '</span>' +
            R.issueLink(s.id, R.esc(s.tracker) + ' #' + s.id) + ' ' + R.esc(s.subject) +
          '</div>' +
          '<div class="rm-story__meta">' +
            '<span class="rm-pill">' + R.dot(s.color) + R.esc(s.status) + '</span>' +
            '<span class="rm-small rm-assignee">' + R.esc(s.assignee || R.t.unassigned) + '</span>' +
            (s.sp !== null && s.sp !== undefined ? '<span class="rm-small">' + R.fmtSp(s.sp) + ' ' + R.esc(R.t.sp) + '</span>' : '') +
            R.storyPhase(s) +
          '</div>' +
        '</div>' +
        (s.excluded ? '' : (s.ready || s.dev_done
          ? R.splitBar(s.ready ? 100 : 0, 100, null, 'rm-bar--thin rm-mt-sm rm-story__bar')
          : '<div class="rm-bar rm-bar--thin rm-mt-sm rm-story__bar"><i style="width:' + s.progress + '%"></i></div>')) +
      '</div>';
    }).join('');

    R.showDrawer('detail');
    $('#rm-detail-body').html(
      R.backLink() +
      '<div class="rm-detail__top">' +
        '<div class="rm-eyebrow">' + R.esc(R.t.epic_execution) + (R.isPortfolio() ? ' · ' + R.esc(product.name) : '') + '</div>' +
        '<button type="button" class="rm-icon-btn" data-rm-close title="' + R.esc(R.t.close) + '" aria-label="' + R.esc(R.t.close) + '">&times;</button>' +
      '</div>' +
      '<h3 class="rm-detail__title">' + R.issueLink(epic.id, '#' + epic.id) + ' ' + R.esc(epic.subject) + '</h3>' +
      '<div class="rm-sub">' + (epic.priority ? R.priorityBadge(epic) + ' · ' : '') +
        R.esc(R.t.owner) + ': ' + R.esc(epic.owner || R.t.unassigned) + ' · ' + epic.story_count + ' ' + R.esc(R.t.stories) + '</div>' +
      '<div class="rm-detail__pills rm-mt-sm">' + pills + '</div>' +
      R.hintBox(epic, product) +
      (product.can_manage ? R.planControls(epic) : '') +
      R.dependencies(epic, product) +
      '<div class="rm-detail__stories-head">' +
        '<b>' + R.esc(R.t.stories) + ' (' + epic.done_count + '/' + epic.story_count + ')</b>' +
        (product.can_add ? '<button type="button" class="rm-btn rm-btn--primary rm-btn--sm" data-rm-new-ticket>+ ' + R.esc(R.t.new_story) + '</button>' : '') +
      '</div>' +
      '<div class="rm-story-grid">' + (rows || '<div class="rm-empty">' + R.esc(R.t.no_stories) + '</div>') + '</div>' +
      R.moveHistory(epic)
    );
  };
})(jQuery);
