// Agile board: Intake source (CS/Sale) badges + client filter
(function (U) {
  if (window.__saIntakeBadgesLoaded) return;
  window.__saIntakeBadgesLoaded = true;

  var mapByIssue = new Map();
  var labels = {
    cs: 'CS',
    sale: 'Sale'
  };

  var projectId = (function () {
    var m = location.pathname.match(/\/projects\/([^\/]+)/);
    return m ? m[1] : null;
  })();

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function (m) {
      return ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[m];
    });
  }

  function ensureExtraWrap(el) {
    var container = el.querySelector('.sa-card-extra');
    if (!container) {
      container = document.createElement('div');
      container.className = 'sa-card-extra';
      var attr = el.querySelector('.attributes, .info, .details, .issue-card-details');
      if (attr && attr.parentNode) attr.parentNode.appendChild(container);
      else el.appendChild(container);
    }
    return container;
  }

  function fetchSourceMap() {
    if (!projectId) return Promise.resolve([]);
    var url = '/projects/' + projectId + '/intake_badges/source_map';
    return fetch(url, {
      headers: { Accept: 'application/json', 'X-Requested-With': 'XMLHttpRequest' },
      credentials: 'same-origin'
    }).then(function (res) {
      return res.ok ? res.json() : [];
    }).catch(function () {
      return [];
    });
  }

  function reconcile(card) {
    if (!mapByIssue.size) return;
    var rawId = U.findIssueId(card);
    if (!rawId) return;
    var id = parseInt(rawId, 10);
    if (isNaN(id)) return;

    var src = mapByIssue.get(id) || null;
    if (card.dataset.intakeSource === (src || '')) return;
    card.dataset.intakeSource = src || '';

    var host = ensureExtraWrap(card);
    var badge = host.querySelector('.sa-intake-badge');
    if (!src) {
      if (badge) badge.remove();
      return;
    }
    if (!badge) {
      badge = document.createElement('span');
      badge.className = 'sa-intake-badge';
      host.insertBefore(badge, host.firstChild);
    }
    badge.className = 'sa-intake-badge sa-intake-badge--' + src;
    badge.textContent = labels[src] || src;
    badge.title = 'Intake: ' + (labels[src] || src);
  }

  function ensureFilterBar() {
    var anchor = document.querySelector('.agile-board-header, #sa-release-filterbar, .agile-board .query-totals, .agile-board');
    if (!anchor) anchor = document.querySelector('#content');
    if (!anchor) return;

    if (!document.getElementById('sa-intake-filterbar')) {
      var bar = document.createElement('div');
      bar.id = 'sa-intake-filterbar';
      bar.innerHTML =
        '<label for="sa-intake-filter"><strong>Intake:</strong></label>' +
        '<select id="sa-intake-filter">' +
          '<option value="">All sources</option>' +
          '<option value="cs">CS</option>' +
          '<option value="sale">Sale</option>' +
          '<option value="product">Product (no CS/Sale)</option>' +
        '</select>' +
        '<button id="sa-intake-clear" type="button">Clear</button>';
      if (anchor.id === 'sa-release-filterbar' && anchor.parentNode) {
        anchor.parentNode.insertBefore(bar, anchor.nextSibling);
      } else {
        anchor.prepend(bar);
      }
    }

    var sel = document.getElementById('sa-intake-filter');
    if (sel && !sel._saBound) {
      sel._saBound = true;
      sel.addEventListener('change', applyFilter);
      document.getElementById('sa-intake-clear').addEventListener('click', function () {
        sel.value = '';
        applyFilter();
      });
    }
  }

  function collectCards() {
    return Array.prototype.slice.call(document.querySelectorAll(
      '.agile-board .issue-card, .agile-board .issue, .agile-card, .agile__issue, .card'
    ));
  }

  function applyFilter() {
    var sel = document.getElementById('sa-intake-filter');
    if (!sel) return;
    var value = sel.value;
    collectCards().forEach(function (el) {
      var src = el.dataset.intakeSource || '';
      var match;
      if (!value) {
        match = true;
      } else if (value === 'product') {
        match = !src;
      } else {
        match = src === value;
      }
      if (match) el.classList.remove('sa-hidden-by-intake');
      else el.classList.add('sa-hidden-by-intake');
    });
  }

  document.addEventListener('DOMContentLoaded', function () {
    fetchSourceMap().then(function (rows) {
      if (!rows || !rows.length) return;
      rows.forEach(function (row) {
        if (row && row.issue_id && row.source) {
          mapByIssue.set(parseInt(row.issue_id, 10), row.source);
        }
      });
      if (!mapByIssue.size) return;
      ensureFilterBar();
      U.register(reconcile);
      U.boot();
      applyFilter();
    });
  });
})(window.SananAgileUtil);
