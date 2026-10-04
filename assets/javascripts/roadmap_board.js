(function ($) {
  'use strict';

  // Product Roadmap — board grid, cards, capacity / baseline / release lines, KPIs, legend.
  var R = window.SananRoadmap = window.SananRoadmap || {};

  R.statusChips = function (epic) {
    var counts = {}, order = [];
    epic.stories.forEach(function (s) {
      if (!counts[s.status_id]) { counts[s.status_id] = { n: 0, color: s.color, name: s.status }; order.push(s.status_id); }
      counts[s.status_id].n += 1;
    });
    return order.map(function (sid) {
      var c = counts[sid];
      return '<span class="rm-chip" title="' + R.esc(c.name) + '">' + R.dot(c.color, 'rm-dot--sm') + c.n + '</span>';
    }).join('');
  };

  // Epic ids added to a quarter after its baseline was captured: { 'productId:quarter': { id: true } }.
  R.addedAfterBaseline = function (product, quarter) {
    var b = product && product.baselines && (product.baselines[String(quarter)] || product.baselines[quarter]);
    var out = {};
    if (b) b.epics.forEach(function (r) { if (r.state === 'added') out[r.id] = true; });
    return out;
  };

  R.epicTags = function (epic, added) {
    var tags = '';
    var mv = epic.moves || {};
    if (epic.span > 1) {
      tags += '<span class="rm-tag rm-tag--span">' + R.esc(R.quarterLabel(epic.year, epic.quarter)) + ' → ' +
        R.esc(R.quarterLabel(epic.end_year, epic.end_quarter)) + '</span>';
    }
    var deps = epic.depends_on || [];
    if (epic.dep_conflict) {
      tags += '<span class="rm-tag rm-tag--late" title="' + R.esc(deps.filter(function (d) { return d.conflict; })
        .map(function (d) { return '#' + d.id + ' ' + d.subject; }).join('\n')) + '">⛓ ' + R.esc(R.t.deps_late_short) + '</span>';
    } else if (deps.length) {
      tags += '<span class="rm-tag">⛓ ' + R.esc(R.fmt(R.t.deps_short, { n: deps.length })) + '</span>';
    }
    if (mv.slipped) {
      tags += '<span class="rm-tag rm-tag--slip" title="' + R.esc(R.fmt(R.t.slip_tip, { n: mv.slips, origin: mv.origin || '?' })) + '">↷ ' +
        R.esc(R.fmt(R.t.slip_short, { n: mv.slips, origin: mv.origin || '?' })) + '</span>';
    }
    if (added && added[epic.id]) tags += '<span class="rm-tag rm-tag--added">' + R.esc(R.t.added_after_baseline) + '</span>';
    return tags ? '<div class="rm-tags">' + tags + '</div>' : '';
  };

  R.epicCard = function (epic, added) {
    var planned = !!epic.quarter;
    var meta = R.esc(epic.status) + (planned ? ' · ' + R.esc(R.healthLabel(epic.health)) : '');
    return '' +
      '<div class="rm-epic' + (R.state.selected === epic.id ? ' is-selected' : '') + (epic.closed ? ' is-closed' : '') +
        '" data-id="' + epic.id + '" tabindex="0" role="button">' +
        (planned ? '<span class="rm-health-stripe" style="background:' + R.HEALTH_COLORS[epic.health] + '"></span>' : '') +
        '<div class="rm-row">' +
          '<div class="rm-titlewrap">' + R.dot(epic.color) +
            '<div><div class="rm-epic__title">' + R.esc(epic.subject) + '</div>' +
            '<div class="rm-meta">#' + epic.id + ' · ' + meta + '</div></div>' +
          '</div>' +
          '<b class="rm-pct">' + (R.hintFor(epic) ? '<span class="rm-hint rm-hint--' + R.hintFor(epic).health + '" title="' +
            R.esc(R.t.hint + ': ' + R.healthLabel(R.hintFor(epic).health) + '\n' + R.hintFor(epic).reasons.join('\n')) + '">!</span> ' : '') +
            epic.progress + '%</b>' +
        '</div>' +
        R.epicTags(epic, added) +
        '<div class="rm-bar rm-mt-sm"><i style="width:' + epic.progress + '%"></i></div>' +
        '<div class="rm-chips">' + R.statusChips(epic) + '</div>' +
        '<div class="rm-epic__extra rm-meta">' +
          R.esc(R.t.owner) + ': ' + R.esc(epic.owner || R.t.unassigned) + ' · ' +
          epic.done_count + '/' + epic.story_count + ' ' + R.esc(R.t.stories) +
          (epic.sp_total ? ' · ' + R.fmtSp(epic.sp_done) + '/' + R.fmtSp(epic.sp_total) + ' ' + R.esc(R.t.sp) : '') +
          ((epic.releases || []).length ? ' · 🚀 ' + R.esc(epic.releases.map(function (r) { return r.name; }).join(', ')) : '') +
        '</div>' +
      '</div>';
  };

  // Suggested health differs from the one set by the PM.
  R.hintFor = function (epic) {
    var s = epic.suggestion;
    return s && epic.quarter && s.health !== epic.health ? s : null;
  };

  // Later quarters of a multi-quarter Epic (read-only, not draggable).
  R.ghostCard = function (c) {
    return '<div class="rm-epic rm-epic--ghost' + (R.state.selected === c.id ? ' is-selected' : '') +
      '" data-ghost-id="' + c.id + '" data-in-data="' + (c.in_data ? '1' : '0') + '" tabindex="0" role="button">' +
      '<div class="rm-row"><div class="rm-titlewrap">' + R.dot(c.color) +
        '<div><div class="rm-epic__title">↳ ' + R.esc(c.subject) + '</div>' +
        '<div class="rm-meta">#' + c.id + ' · ' + R.esc(R.fmt(R.t.continues_from, { from: c.from })) + '</div></div></div>' +
        '<b class="rm-pct">' + c.progress + '%</b></div>' +
    '</div>';
  };

  // Grid skeleton (header + one row per product). Lists are filled by R.renderLists().
  // Past quarters get a narrower, muted column: planning happens in the current and future ones.
  R.gridColumns = function () {
    var mins = 150;
    var cols = R.QUARTERS.map(function (q) {
      if (R.isPastQuarter(q)) { mins += 120; return 'minmax(120px, .6fr)'; }
      mins += 170;
      return 'minmax(170px, 1fr)';
    });
    return 'grid-template-columns: 150px ' + cols.join(' ') + '; min-width: ' + mins + 'px';
  };

  R.renderBoard = function () {
    var cq = Number(R.data.current_quarter) || 0;
    var months = R.t.months || [];
    var gridStyle = ' style="' + R.gridColumns() + '"';
    var qClass = function (q) { return (q === cq ? ' is-current' : '') + (R.isPastQuarter(q) ? ' is-past' : ''); };
    // Picker shortcut only for the empty portfolio (the toolbar keeps the main "Products" picker).
    var pickBtn = R.isPortfolio() && document.getElementById('rm-picker')
      ? '<button type="button" class="rm-pick-btn" data-rm-open-picker>＋ ' + R.esc(R.t.choose_products) + '</button>' : '';
    var head = '<div class="rm-grid rm-head"' + gridStyle + '><div class="rm-cell rm-small rm-head__product"><b>' + R.esc(R.t.workstream) + '</b></div>' +
      R.QUARTERS.map(function (q) {
        return '<div class="rm-cell rm-q' + qClass(q) + '">' +
          '<div class="rm-q__top"><b>Q' + q + '</b>' +
          '<span class="rm-q__meta">' + R.esc(months[(q - 1) * 3 + 1] || '') + ' – ' + R.esc(months[q * 3] || '') +
          ' · <span data-rm-qcount="' + q + '"></span></span></div>' +
        '</div>';
      }).join('') + '</div>';

    var rows = R.data.products.map(function (p) {
      var name = R.isPortfolio() && p.urls.roadmap
        ? '<a class="rm-prodname" href="' + R.esc(p.urls.roadmap) + '" title="' + R.esc(R.t.open_product) + '">' + R.esc(p.name) + '</a>'
        : '<div class="rm-prodname">' + R.esc(p.name) + '</div>';
      return '<div class="rm-grid rm-product-row" data-product="' + p.id + '"' + gridStyle + '>' +
        '<div class="rm-cell rm-product">' +
          name +
          (p.parent_name ? '<div class="rm-small">' + R.esc(p.parent_name) + '</div>' : '') +
          (p.epic_tracker_id ? '' : '<div class="rm-small rm-qcap__warn rm-mt-xs">' + R.esc(R.t.no_epic_tracker) + '</div>') +
          '<div class="rm-small rm-mt">' + R.esc(R.t.portfolio_progress) + '</div>' +
          '<div class="rm-bar rm-mt-xs"><i data-rm-progress-bar style="width:0%"></i></div>' +
          '<div class="rm-small rm-strong rm-mt-xs" data-rm-progress-pct>0%</div>' +
          '<div class="rm-small rm-mt-xs" data-rm-progress-sp></div>' +
        '</div>' +
        R.QUARTERS.map(function (q) {
          return '<div class="rm-quarter' + qClass(q) + '" data-quarter-cell="' + q + '">' +
            '<div class="rm-qcap" data-rm-qcap="' + q + '"></div>' +
            '<div class="rm-qbase" data-rm-qbase="' + q + '"></div>' +
            '<div class="rm-qrel" data-rm-qrel="' + q + '"></div>' +
            '<div class="rm-list" data-product="' + p.id + '" data-quarter="' + q + '"></div>' +
            (p.can_add ? '<button type="button" class="rm-add" data-rm-add="' + q + '">+ ' + R.esc(R.t.add_epic) + '</button>' : '') +
          '</div>';
        }).join('') +
      '</div>';
    }).join('');

    $('#rm-board').html(head + (rows || '<div class="rm-empty rm-empty--board">' + R.esc(R.t.no_products) +
      (pickBtn ? '<div class="rm-mt-sm">' + pickBtn + '</div>' : '') + '</div>'));

    // Unplanned backlog lives in the right drawer (only products the user can plan).
    var trays = R.data.products.filter(function (p) { return p.can_manage; });
    R.$root.find('[data-rm-backlog]').prop('hidden', trays.length === 0);
    $('#rm-unplanned-body').html(trays.map(function (p) {
      return '<div class="rm-unplanned__group">' +
        '<div class="rm-unplanned__group-head">' +
          (R.data.products.length > 1 ? '<span class="rm-team__role">' + R.esc(p.name) + '</span>' : '<span></span>') +
          (p.can_add ? '<button type="button" class="rm-btn rm-btn--primary rm-btn--sm" data-rm-add-unplanned="' + p.id + '">+ ' +
            R.esc(R.t.add_epic) + '</button>' : '') +
        '</div>' +
        '<div class="rm-list rm-list--tray" data-product="' + p.id + '" data-quarter="0"></div>' +
      '</div>';
    }).join(''));

    R.initSortable();
  };

  R.renderLists = function () {
    R.$root.find('.rm-list').each(function () {
      var $list = $(this);
      var product = R.productById($list.attr('data-product'));
      if (!product) return;
      var quarter = $list.attr('data-quarter');
      var epics = R.listFor(product, quarter) || [];
      var added = Number(quarter) ? R.addedAfterBaseline(product, quarter) : {};
      var html = epics.filter(R.epicVisible).map(function (e) { return R.epicCard(e, added); }).join('');
      if (Number(quarter) && !R.filtersActive()) {
        html += ((product.continuations || {})[String(quarter)] || []).map(R.ghostCard).join('');
      }
      // Empty quarter: the "+ Epic" action is the empty state (no separate placeholder).
      // No new Epics in a quarter that is already over.
      var addable = Number(quarter) && product.can_add && !R.isPastQuarter(Number(quarter));
      if (!html) {
        html = addable && !R.filtersActive()
          ? '<button type="button" class="rm-empty rm-empty--add" data-rm-add="' + quarter + '">+ ' + R.esc(R.t.add_epic) + '</button>'
          : '<div class="rm-empty">' + R.esc(R.t.no_epics) + '</div>';
      }
      $list.html(html);
      $list.siblings('.rm-add').prop('hidden', !addable || !$list.children('.rm-epic').length);
    });
    R.QUARTERS.forEach(function (q) {
      var n = R.data.products.reduce(function (sum, p) { return sum + p.quarters[String(q)].length; }, 0);
      R.$root.find('[data-rm-qcount="' + q + '"]').text(R.epicCount(n));
    });
    $('#rm-unplanned-count').text(R.data.products.reduce(function (sum, p) { return sum + p.unplanned.length; }, 0));

    var $lists = R.$root.find('.rm-list');
    $lists.each(function () {
      var $l = $(this);
      if ($l.sortable('instance')) {
        $l.sortable('option', 'disabled', R.filtersActive());
        $l.sortable('refresh');
      }
    });
  };

  R.renderKpis = function () {
    var epics = R.plannedEpics();
    var all = R.progressOf(epics);
    var risk = epics.filter(function (e) { return e.health !== 'on_track'; }).length;
    var kpis = [
      [R.t.kpi_epics, epics.length],
      [R.t.kpi_stories, all.stories],
      [R.t.kpi_done, all.done + '/' + all.stories],
      [R.t.kpi_sp, R.fmtSp(all.spDone) + '/' + R.fmtSp(all.spTotal)],
      [R.t.kpi_risk, risk]
    ];
    if (R.isPortfolio()) kpis.unshift([R.t.products, R.data.products.length]);
    $('#rm-kpis').html(kpis.map(function (k) {
      return '<div class="rm-kpi"><div class="rm-kpi__l">' + R.esc(k[0]) + '</div><div class="rm-kpi__v">' + R.esc(k[1]) + '</div></div>';
    }).join(''));

    R.data.products.forEach(function (p) {
      var pr = R.progressOf(R.plannedEpics(p));
      var $row = R.$root.find('.rm-product-row[data-product="' + p.id + '"]');
      $row.find('[data-rm-progress-bar]').css('width', pr.pct + '%');
      $row.find('[data-rm-progress-pct]').text(pr.pct + '%');
      $row.find('[data-rm-progress-sp]').text(pr.spTotal > 0 ? R.fmtSp(pr.spDone) + '/' + R.fmtSp(pr.spTotal) + ' ' + R.t.sp : '');
    });
  };

  // Per product × quarter: remaining SP of planned (open) Epics vs. velocity × sprints left.
  R.renderCapacity = function () {
    R.data.products.forEach(function (p) {
      var quarters = (p.capacity && p.capacity.quarters) || {};
      var $row = R.$root.find('.rm-product-row[data-product="' + p.id + '"]');
      R.QUARTERS.forEach(function (q) {
        var $slot = $row.find('[data-rm-qcap="' + q + '"]');
        var info = quarters[String(q)] || quarters[q];
        if (!info || info.past) { $slot.empty().removeClass('is-over'); return; }

        // A multi-quarter Epic's remaining SP is spread evenly over the quarters it spans.
        var remaining = 0, noSp = 0;
        R.plannedEpics(p).forEach(function (e) {
          if (e.closed) return;
          var start = e.year * 4 + e.quarter - 1;
          var end = (e.end_year || e.year) * 4 + (e.end_quarter || e.quarter) - 1;
          var key = R.data.year * 4 + q - 1;
          if (key < start || key > end) return;
          remaining += Math.max((Number(e.sp_total) || 0) - (Number(e.sp_done) || 0), 0) / (end - start + 1);
          if (key === start) e.stories.forEach(function (s) { if (!s.closed && (s.sp === null || s.sp === undefined)) noSp += 1; });
        });
        var capacity = Number(info.capacity) || 0;
        var over = capacity > 0 && remaining > capacity;
        var pct = capacity > 0 ? Math.min(Math.round(remaining / capacity * 100), 100) : 0;
        var tip = R.t.cap_remaining + ' ' + R.fmtSp(remaining) + ' SP / ' + R.t.cap_capacity + ' ' +
          (capacity > 0 ? R.fmtSp(capacity) + ' SP · ' + R.fmt(R.t.cap_sprints, { n: info.sprints }) : R.t.cap_no_velocity);
        var warns = [];
        if (over) warns.push(R.fmt(R.t.cap_over, { n: R.fmtSp(remaining - capacity) }));
        if (noSp) warns.push(R.fmt(R.t.cap_no_sp, { n: noSp }));
        $slot.html(
          '<div class="rm-qcap__row" title="' + R.esc(tip) + '">' +
            '<span class="rm-qcap__num">' + R.esc(R.t.cap_remaining) + ' <b>' + R.fmtSp(remaining) + '</b>/' +
              (capacity > 0 ? R.fmtSp(capacity) : '—') + ' SP</span>' +
            (capacity > 0 ? '<span class="rm-bar rm-bar--thin rm-qcap__bar"><i style="width:' + pct + '%"></i></span>' +
              '<span class="rm-qcap__sprints">' + R.esc(R.fmt(R.t.cap_sprints_short, { n: info.sprints })) + '</span>' : '') +
          '</div>' +
          (warns.length ? '<div class="rm-qcap__warn">' + R.esc(warns.join(' · ')) + '</div>' : '')
        ).toggleClass('is-over', over);
      });
    });
  };

  // Per product × quarter: baseline summary (opens the review) or a "lock plan" action.
  R.renderBaselines = function () {
    R.data.products.forEach(function (p) {
      var $row = R.$root.find('.rm-product-row[data-product="' + p.id + '"]');
      R.QUARTERS.forEach(function (q) {
        var $slot = $row.find('[data-rm-qbase="' + q + '"]');
        var b = R.baselineFor(p, q);
        var past = (p.capacity && p.capacity.quarters && (p.capacity.quarters[String(q)] || {}).past) || false;
        if (b) {
          var c = b.summary.counts;
          var bits = [R.fmt(R.t.bl_done_short, { n: c.done, total: b.summary.committed_epics })];
          if (c.slipped) bits.push(R.fmt(R.t.bl_slipped_short, { n: c.slipped }));
          if (c.added) bits.push(R.fmt(R.t.bl_added_short, { n: c.added }));
          $slot.html('<button type="button" class="rm-qbase__btn' + (R.state.review && R.state.review.productId === p.id && R.state.review.quarter === q ? ' is-active' : '') +
            '" data-rm-review="' + q + '" title="' + R.esc(R.t.bl_open) + '">📌 ' + R.esc(R.fmt(R.t.bl_line, { date: b.captured_at })) +
            ' · ' + R.esc(bits.join(' · ')) + '</button>');
        } else if (p.can_manage && !past && (p.quarters[String(q)] || []).length) {
          $slot.html('<button type="button" class="rm-qbase__lock" data-rm-baseline-create="' + q + '" title="' + R.esc(R.t.bl_lock_tip) + '">📌 ' +
            R.esc(R.t.bl_lock) + '</button>');
        } else {
          $slot.empty();
        }
      });
    });
  };

  // Releases due in each quarter (Releases module).
  R.renderReleases = function () {
    R.data.products.forEach(function (p) {
      var $row = R.$root.find('.rm-product-row[data-product="' + p.id + '"]');
      R.QUARTERS.forEach(function (q) {
        var list = (p.releases || {})[String(q)] || [];
        $row.find('[data-rm-qrel="' + q + '"]').html(list.map(function (r) {
          return '<a class="rm-rel rm-rel--' + R.esc(r.state) + '" href="' + R.esc(r.url) + '" title="' +
            R.esc(r.name + ' · ' + r.release_on + ' · ' + ((R.t.rel_state || {})[r.state] || r.state)) + '">🚀 ' + R.esc(r.name) +
            ' <span>' + R.esc(String(r.release_on).slice(5).split('-').reverse().join('/')) + '</span></a>';
        }).join(''));
      });
    });
  };

  R.renderOwnerFilter = function () {
    var owners = {};
    R.data.products.forEach(function (p) {
      R.plannedEpics(p).concat(p.unplanned).forEach(function (e) { if (e.owner) owners[e.owner] = true; });
    });
    var $sel = $('#rm-filter-owner');
    var current = R.state.owner;
    $sel.find('option:not(:first)').remove();
    Object.keys(owners).sort().forEach(function (o) {
      $sel.append($('<option>').val(o).text(o).prop('selected', o === current));
    });
  };

  R.renderLegend = function () {
    // Colors as rendered on the cards (each product may configure its own status colors).
    var used = {}, order = [];
    function add(statusId, name, color) {
      var k = statusId + '|' + color;
      if (used[k]) return;
      used[k] = true;
      order.push({ id: statusId, name: name, color: color });
    }
    R.data.products.forEach(function (p) {
      R.plannedEpics(p).concat(p.unplanned).forEach(function (e) {
        add(e.status_id, e.status, e.color);
        e.stories.forEach(function (s) { add(s.status_id, s.status, s.color); });
      });
    });
    var pos = {};
    (R.data.statuses || []).forEach(function (s, i) { pos[s.id] = i; });
    order.sort(function (a, b) { return (pos[a.id] || 0) - (pos[b.id] || 0); });
    $('#rm-legend').html(order.map(function (s) {
      return '<span class="rm-chip">' + R.dot(s.color, 'rm-dot--sm') + R.esc(s.name) + '</span>';
    }).join(''));
  };

  // Everything except the grid skeleton (keeps sortable instances alive).
  R.renderAll = function () {
    R.renderLists();
    R.renderKpis();
    R.renderTeam();
    R.renderCapacity();
    R.renderBaselines();
    R.renderReleases();
    R.renderOwnerFilter();
    R.renderLegend();
    R.renderDetail();
  };
})(jQuery);
