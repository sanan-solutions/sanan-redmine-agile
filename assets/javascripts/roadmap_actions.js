(function ($) {
  'use strict';

  // Product Roadmap — drag & drop, saving, refresh and event bindings.
  var R = window.SananRoadmap = window.SananRoadmap || {};

  var refreshTimer = null;

  R.orderedIds = function (product, quarter) {
    return (R.listFor(product, quarter) || []).map(function (e) { return e.id; });
  };

  R.placeEpic = function (product, epic, year, quarter, index) {
    var found = R.findEpic(epic.id);
    if (found) found.list.splice(found.index, 1);
    if (Number(year) !== Number(R.data.year) && Number(quarter) !== 0) return; // moved out of the shown year
    epic.year = Number(quarter) === 0 ? null : Number(year);
    epic.quarter = Number(quarter) === 0 ? null : Number(quarter);
    var list = R.listFor(product, quarter);
    if (index === undefined || index < 0 || index > list.length) index = list.length;
    list.splice(index, 0, epic);
  };

  R.saveMove = function (product, epic, year, quarter) {
    return R.request('PATCH', product.urls.move, {
      issue_id: epic.id,
      year: year,
      quarter: quarter,
      ordered_ids: Number(year) === Number(R.data.year) ? R.orderedIds(product, quarter) : []
    });
  };

  // Redmine's own new-issue form in the plugin's global modal; full page as fallback.
  R.openCreate = function (url, pendingEpic) {
    R.state.pendingEpic = pendingEpic;
    if (window.SANAN_globalModal) {
      window.SANAN_globalModal.createIssue(url);
    } else {
      window.location.href = url;
    }
  };

  R.scheduleRefresh = function () {
    clearTimeout(refreshTimer);
    refreshTimer = setTimeout(function () {
      $.ajax({
        url: R.$root.attr('data-data-url'),
        dataType: 'json',
        headers: { 'X-Requested-With': 'XMLHttpRequest' }
      }).done(function (fresh) {
        R.setData(fresh);
        R.renderBoard();
        R.renderAll();
      });
    }, 250);
  };

  // Drag & drop stays inside one product: an Epic belongs to its project.
  R.initSortable = function () {
    if (!$.fn.sortable) return;
    R.data.products.forEach(function (p) {
      if (!p.can_manage) return;
      var selector = '#sanan-roadmap .rm-list[data-product="' + p.id + '"]';
      $(selector).sortable({
        items: '.rm-epic:not(.rm-epic--ghost)',
        connectWith: selector,
        placeholder: 'rm-placeholder',
        forcePlaceholderSize: true,
        distance: 4,
        tolerance: 'pointer',
        disabled: R.filtersActive(),
        // The dragged card is a clone attached to the page root, so neither the drawer nor the board's
        // scroll box clips it while it travels between them.
        helper: 'clone',
        appendTo: '#sanan-roadmap',
        zIndex: 1000,
        start: function (e, ui) {
          ui.helper.addClass('rm-epic--dragging').css('width', ui.item.outerWidth());
          ui.placeholder.css('height', ui.item.outerHeight());
          R.$root.addClass('is-dragging');
          $(selector).addClass('is-drop-target');
        },
        over: function () { $(this).addClass('is-drag-over'); },
        out: function () { $(this).removeClass('is-drag-over'); },
        stop: function (e, ui) {
          R.$root.removeClass('is-dragging');
          $(selector).removeClass('is-drop-target is-drag-over');
          var id = Number(ui.item.attr('data-id'));
          var $list = ui.item.closest('.rm-list');
          var quarter = Number($list.attr('data-quarter'));
          var index = $list.children('.rm-epic:not(.rm-epic--ghost)').index(ui.item);
          var found = R.findEpic(id);
          if (!found) return;
          var prevQuarter = found.epic.quarter || 0;
          if (prevQuarter === quarter && found.index === index) return;
          R.placeEpic(p, found.epic, R.data.year, quarter, index);
          if (quarter !== 0 && !prevQuarter) found.epic.health = 'on_track';
          R.renderAll();
          R.saveMove(p, found.epic, R.data.year, quarter).fail(function () { window.location.reload(); });
        }
      });
    });
  };

  R.bindEvents = function () {
    R.$root.on('click keydown', '.rm-epic:not(.rm-epic--ghost)', function (e) {
      if (e.type === 'keydown' && e.key !== 'Enter' && e.key !== ' ') return;
      e.preventDefault();
      var id = Number($(this).attr('data-id'));
      R.state.selected = R.state.selected === id ? null : id;
      R.state.review = null;
      R.renderLists();
      R.renderBaselines();
      R.renderDetail();
    });

    // Baseline: open review / lock plan / re-lock / delete.
    R.$root.on('click', '[data-rm-review]', function () {
      var productId = Number($(this).closest('.rm-product-row').attr('data-product'));
      var quarter = Number($(this).attr('data-rm-review'));
      var same = R.state.review && R.state.review.productId === productId && R.state.review.quarter === quarter;
      R.state.review = same ? null : { productId: productId, quarter: quarter };
      R.state.selected = null;
      R.renderLists();
      R.renderBaselines();
      R.renderDetail();
    });
    R.$root.on('click', '[data-rm-select]', function (e) {
      e.preventDefault();
      R.state.review = null;
      R.state.selected = Number($(this).attr('data-rm-select'));
      R.renderLists();
      R.renderBaselines();
      R.renderDetail();
    });
    function captureBaseline(product, quarter, confirmMsg) {
      if (confirmMsg && !window.confirm(confirmMsg)) return;
      R.request('POST', product.urls.baseline, { year: R.data.year, quarter: quarter }).done(function () {
        R.state.review = { productId: product.id, quarter: quarter };
        R.state.selected = null;
        R.scheduleRefresh();
      });
    }
    R.$root.on('click', '[data-rm-baseline-create]', function () {
      var product = R.productById($(this).closest('.rm-product-row').attr('data-product'));
      var quarter = Number($(this).attr('data-rm-baseline-create'));
      if (product) captureBaseline(product, quarter, R.fmt(R.t.bl_lock_confirm, { q: 'Q' + quarter + '/' + R.data.year }));
    });
    R.$root.on('click', '[data-rm-rebaseline]', function () {
      var product = R.state.review && R.productById(R.state.review.productId);
      if (product) captureBaseline(product, R.state.review.quarter, R.t.bl_relock_confirm);
    });
    R.$root.on('click', '[data-rm-baseline-delete]', function () {
      var product = R.state.review && R.productById(R.state.review.productId);
      if (!product || !window.confirm(R.t.bl_delete_confirm)) return;
      R.request('DELETE', product.urls.baseline, { year: R.data.year, quarter: R.state.review.quarter }).done(function () {
        R.state.review = null;
        R.scheduleRefresh();
      });
    });

    function refreshDrawer() {
      R.renderLists();
      R.renderBaselines();
      R.renderDetail();
    }

    // × closes the whole drawer (detail, review and backlog).
    R.$root.on('click', '[data-rm-close]', function () {
      R.state.review = null;
      R.state.selected = null;
      R.state.backlog = false;
      refreshDrawer();
    });

    // Unplanned backlog drawer: toggle from the toolbar, close, or go back to it from a detail.
    R.$root.on('click', '[data-rm-backlog]', function () {
      R.state.backlog = !(R.state.backlog && !R.state.selected && !R.state.review);
      R.state.selected = null;
      R.state.review = null;
      refreshDrawer();
    });
    R.$root.on('click', '[data-rm-backlog-close]', function () {
      R.state.backlog = false;
      refreshDrawer();
    });
    R.$root.on('click', '[data-rm-back-backlog]', function () {
      R.state.selected = null;
      R.state.review = null;
      refreshDrawer();
    });

    // Esc steps back: detail/review → backlog (if it was open) → closed.
    $(document).on('keydown', function (e) {
      if (e.key !== 'Escape' || $('#global-modal').is(':visible')) return;
      if (R.state.selected || R.state.review) {
        R.state.selected = null;
        R.state.review = null;
      } else if (R.state.backlog) {
        R.state.backlog = false;
      } else {
        return;
      }
      refreshDrawer();
    });

    R.$root.on('click', '.rm-issue-link', function (e) {
      if (!window.SANAN_globalModal || e.metaKey || e.ctrlKey || e.shiftKey || e.button === 1) return;
      e.preventDefault();
      R.state.pendingEpic = null;
      window.SANAN_globalModal.viewIssue($(this).attr('data-issue-id'));
    });

    R.$root.on('click', '[data-rm-new-ticket]', function () {
      var found = R.findEpic(R.state.selected);
      if (!found) return;
      R.openCreate(R.newIssueUrl(found.product, { parent_issue_id: found.epic.id }), null);
    });

    // New Epic straight into the Unplanned backlog (no quarter): it shows up there after the refresh.
    R.$root.on('click', '[data-rm-add-unplanned]', function () {
      var product = R.productById($(this).attr('data-rm-add-unplanned'));
      if (!product) return;
      R.openCreate(R.newIssueUrl(product, { tracker_id: product.epic_tracker_id }), null);
    });

    R.$root.on('click', '[data-rm-add]', function () {
      var product = R.productById($(this).closest('.rm-product-row').attr('data-product'));
      if (!product) return;
      var quarter = Number($(this).attr('data-rm-add'));
      R.openCreate(R.newIssueUrl(product, { tracker_id: product.epic_tracker_id }),
        { productId: product.id, year: R.data.year, quarter: quarter });
    });

    $(document).on('sanan:issue-saved', function (e) {
      var detail = (e.originalEvent && e.originalEvent.detail) || e.detail || {};
      var pending = R.state.pendingEpic;
      var product = pending && R.productById(pending.productId);
      if (product && detail.isCreate && detail.issueId) {
        R.state.pendingEpic = null;
        // Place the new Epic in the quarter it was created from (ignored if tracker was changed).
        $.ajax({
          url: product.urls.move,
          type: 'PATCH',
          dataType: 'json',
          headers: { 'X-CSRF-Token': R.csrfToken(), 'X-Requested-With': 'XMLHttpRequest' },
          data: { issue_id: detail.issueId, year: pending.year, quarter: pending.quarter,
                  ordered_ids: R.orderedIds(product, pending.quarter).concat([Number(detail.issueId)]) }
        }).always(R.scheduleRefresh);
        return;
      }
      R.scheduleRefresh();
    });

    $('#rm-filter-status').on('change', function () { R.state.status = this.value; R.renderLists(); R.renderDetail(); });
    $('#rm-filter-owner').on('change', function () { R.state.owner = this.value; R.renderLists(); });
    var searchTimer = null;
    $('#rm-search').on('input', function () {
      var v = $.trim(this.value);
      clearTimeout(searchTimer);
      searchTimer = setTimeout(function () { R.state.q = v; R.renderLists(); }, 150);
    });
    R.$root.on('click', '[data-rm-print]', function () { window.print(); });

    // Ghost (continuation) card: select the Epic when it is on this board, else open the issue.
    R.$root.on('click keydown', '.rm-epic--ghost', function (e) {
      if (e.type === 'keydown' && e.key !== 'Enter' && e.key !== ' ') return;
      e.preventDefault();
      var id = Number($(this).attr('data-ghost-id'));
      if ($(this).attr('data-in-data') === '1') {
        R.state.selected = id;
        R.state.review = null;
        R.renderLists();
        R.renderBaselines();
        R.renderDetail();
      } else if (window.SANAN_globalModal) {
        window.SANAN_globalModal.viewIssue(id);
      } else {
        window.location.href = R.issueUrl(id);
      }
    });

    R.$root.on('click', '[data-rm-hint-apply]', function () {
      var found = R.findEpic(R.state.selected);
      if (!found) return;
      var health = $(this).attr('data-rm-hint-apply');
      R.request('PATCH', found.product.urls.health, { issue_id: found.epic.id, health: health }).done(function (res) {
        found.epic.health = res.health || health;
        R.renderAll();
      });
    });

    R.$root.on('change', '[data-rm-span]', function () {
      var found = R.findEpic(R.state.selected);
      if (!found) return;
      R.request('PATCH', found.product.urls.span, { issue_id: found.epic.id, span: this.value }).done(R.scheduleRefresh);
    });
    $('#rm-filter-health').on('change', function () { R.state.health = this.value; R.renderLists(); });

    R.$root.on('click', '[data-rm-view]', function () {
      var view = $(this).attr('data-rm-view');
      R.$root.toggleClass('is-compact', view === 'compact');
      R.$root.find('[data-rm-view]').removeClass('is-active');
      $(this).addClass('is-active');
      try { window.localStorage.setItem('sananRoadmapView', view); } catch (err) { /* ignore */ }
    });

    R.$root.on('change', '[data-rm-health]', function () {
      var found = R.findEpic(R.state.selected);
      if (!found) return;
      var health = this.value;
      R.request('PATCH', found.product.urls.health, { issue_id: found.epic.id, health: health }).done(function (res) {
        found.epic.health = res.health || health;
        R.renderAll();
      });
    });

    R.$root.on('change', '[data-rm-plan-quarter], [data-rm-plan-year]', function () {
      var found = R.findEpic(R.state.selected);
      if (!found) return;
      var year = Number(R.$root.find('[data-rm-plan-year]').val());
      var quarter = Number(R.$root.find('[data-rm-plan-quarter]').val());
      if (quarter !== 0 && !(year >= 2000 && year <= 2199)) return;
      if (quarter === (found.epic.quarter || 0) && (quarter === 0 || year === found.epic.year)) return;
      var epic = found.epic;
      var wasPlanned = !!epic.quarter;
      R.placeEpic(found.product, epic, year, quarter);
      if (quarter !== 0 && !wasPlanned) epic.health = 'on_track';
      if (!R.findEpic(epic.id)) R.state.selected = null;
      R.renderAll();
      R.saveMove(found.product, epic, year, quarter).fail(function () { window.location.reload(); });
    });

    // Product picker (portfolio page).
    R.$root.on('click', '[data-rm-open-picker]', function (e) {
      e.stopPropagation();
      var picker = document.getElementById('rm-picker');
      if (!picker) return;
      picker.open = true;
      picker.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    });
    R.$root.on('click', '[data-rm-pick]', function () {
      var on = $(this).attr('data-rm-pick') === 'all';
      $(this).closest('form').find('input[name="project_ids[]"]').prop('checked', on);
    });
    $(document).on('click', function (e) {
      var picker = document.getElementById('rm-picker');
      if (picker && picker.open && !picker.contains(e.target)) picker.open = false;
    });

    // Remember collapsible sections.
    var drawerFrame = null;
    $(window).on('scroll resize', function () {
      if (drawerFrame || !R.$root.hasClass('has-detail')) return;
      drawerFrame = window.requestAnimationFrame(function () { drawerFrame = null; R.syncDrawerTop(); });
    });

    // Team & Capacity starts collapsed (keeps the board above the fold); the choice is remembered.
    ['rm-team'].forEach(function (id) {
      var el = document.getElementById(id);
      if (!el) return;
      var key = 'sananRoadmap:' + id + (R.isPortfolio() ? ':portfolio' : '') + ':v2';
      try { el.open = window.localStorage.getItem(key) === '1'; } catch (err) { /* ignore */ }
      $(el).on('toggle', function () {
        try { window.localStorage.setItem(key, this.open ? '1' : '0'); } catch (err) { /* ignore */ }
      });
    });
  };
})(jQuery);
