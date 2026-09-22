// Agile board: Epic client filter (parent epic / inherited from story parent)
(function (U) {
  if (window.__saEpicFilterLoaded) return;
  window.__saEpicFilterLoaded = true;

  var mapByIssue = new Map();
  var epics = [];

  var projectId = (function () {
    var m = location.pathname.match(/\/projects\/([^\/]+)/);
    return m ? m[1] : null;
  })();

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function (m) {
      return ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[m];
    });
  }

  function fetchEpicMap() {
    if (!projectId) return Promise.resolve({ epics: [], issues: [] });
    return fetch('/projects/' + projectId + '/epic_badges/epic_map', {
      headers: { Accept: 'application/json', 'X-Requested-With': 'XMLHttpRequest' },
      credentials: 'same-origin'
    }).then(function (res) {
      return res.ok ? res.json() : { epics: [], issues: [] };
    }).catch(function () {
      return { epics: [], issues: [] };
    });
  }

  function reconcile(card) {
    if (!U.findIssueId) return;
    var rawId = U.findIssueId(card);
    if (!rawId) return;
    var id = parseInt(rawId, 10);
    if (isNaN(id)) return;

    var epicId = mapByIssue.get(id);
    if (epicId == null) {
      var parent = parseInt(card.getAttribute('data-parent-id'), 10);
      if (!isNaN(parent) && epics.some(function (e) { return parseInt(e.id, 10) === parent; })) {
        epicId = parent;
      } else {
        epicId = '';
      }
    }
    card.dataset.epicId = epicId ? String(epicId) : '';
  }

  function collectCards() {
    return Array.prototype.slice.call(document.querySelectorAll(
      '.agile-board .issue-card, .agile-board .agile-card, .agile-board .agile__issue'
    ));
  }

  function applyFilter() {
    var sel = document.getElementById('sa-epic-filter');
    if (!sel) return;
    var value = sel.value;
    collectCards().forEach(function (el) {
      var epicId = el.dataset.epicId || '';
      var match = !value || (value === '__none__' ? !epicId : epicId === value);
      if (match) el.classList.remove('sa-hidden-by-epic');
      else el.classList.add('sa-hidden-by-epic');
    });
    if (U.syncBoardColumnCounts) U.syncBoardColumnCounts();
  }

  function ensureFilterBar() {
    if (!U.ensureBoardFilterField || !epics.length) return;
    var html = '<label for="sa-epic-filter"><strong>Epic:</strong></label>' +
      '<select id="sa-epic-filter"><option value="">All epics</option></select>';
    var sel = U.ensureBoardFilterField('sa-epic-filter', html, 12);
    if (!sel) return;
    var current = sel.value;
    var opts = '<option value="">All epics</option>' +
      '<option value="__none__">No epic</option>';
    epics.forEach(function (e) {
      opts += '<option value="' + escapeHtml(String(e.id)) + '">' + escapeHtml(e.name) + '</option>';
    });
    sel.innerHTML = opts;
    if (current && Array.prototype.some.call(sel.options, function (o) { return o.value === current; })) {
      sel.value = current;
    }
    if (!sel._saBound) {
      sel._saBound = true;
      sel.addEventListener('change', applyFilter);
    }
  }

  document.addEventListener('DOMContentLoaded', function () {
    fetchEpicMap().then(function (data) {
      epics = (data && data.epics) || [];
      ((data && data.issues) || []).forEach(function (row) {
        if (row && row.issue_id && row.epic_id) {
          mapByIssue.set(parseInt(row.issue_id, 10), parseInt(row.epic_id, 10));
        }
      });
      if (!epics.length) return;
      ensureFilterBar();
      if (U && U.register) {
        U.register(reconcile);
        if (U.boot) U.boot();
      } else {
        collectCards().forEach(reconcile);
      }
      applyFilter();
    });
  });
})(window.SananAgileUtil);
