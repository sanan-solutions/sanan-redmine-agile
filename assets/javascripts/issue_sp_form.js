(function (w, d) {
  var FIBO = [0, 0.5, 1, 2, 3, 5, 8, 13, 21, 34];

  function parseNum(v) {
    var s = String(v || '').trim().replace(',', '.');
    if (!s) return null;
    var n = parseFloat(s);
    return isNaN(n) ? null : n;
  }

  function fmt(n) {
    if (n == null) return '';
    return (Math.round(n) === n) ? String(n) : String(n);
  }

  function nearestFibo(n) {
    var best = FIBO[0];
    var bestScore = [Math.abs(FIBO[0] - n), -FIBO[0]];
    for (var i = 1; i < FIBO.length; i++) {
      var v = FIBO[i];
      var score = [Math.abs(v - n), -v];
      if (score[0] < bestScore[0] || (score[0] === bestScore[0] && score[1] < bestScore[1])) {
        best = v;
        bestScore = score;
      }
    }
    return best;
  }

  function meta(root) {
    return root.querySelector('#sanan-sp-hide-cfs');
  }

  function formulaOf(root) {
    var m = meta(root);
    var f = m ? (m.getAttribute('data-sp-formula') || 'manual') : 'manual';
    return (f === 'max' || f === 'avg') ? f : 'manual';
  }

  function requireQa(root) {
    var m = meta(root);
    return !!(m && m.getAttribute('data-sp-require-qa') === '1');
  }

  function field(root, group, role) {
    return root.querySelector('[data-sanan-sp-group="' + group + '"][data-sanan-sp-role="' + role + '"]');
  }

  function suggested(be, fe, qa, formula, needQa) {
    if (needQa && parseNum(qa) == null) return '';
    var nums = [parseNum(be), parseNum(fe), parseNum(qa)];
    if (formula === 'max') {
      var present = nums.filter(function (n) { return n != null; });
      return present.length ? fmt(Math.max.apply(null, present)) : '';
    }
    if (formula === 'avg') {
      if (nums.every(function (n) { return n == null; })) return '';
      var sum = nums.reduce(function (a, n) { return a + (n == null ? 0 : n); }, 0);
      return fmt(nearestFibo(sum / 3));
    }
    return '';
  }

  function sameSp(a, b) {
    var na = parseNum(a);
    var nb = parseNum(b);
    if (na == null && nb == null) return true;
    if (na == null || nb == null) return false;
    return Math.abs(na - nb) < 0.0001;
  }

  function refreshGroup(root, group) {
    var be = field(root, group, 'be');
    var fe = field(root, group, 'fe');
    var qa = field(root, group, 'qa');
    var tot = field(root, group, 'total');
    if (!tot) return;
    var formula = formulaOf(root);
    var needQa = requireQa(root);
    if (formula === 'manual' && !needQa) return;

    var next = suggested(be && be.value, fe && fe.value, qa && qa.value, formula, needQa);
    var cur = tot.value;
    var last = tot.getAttribute('data-sanan-sp-suggested');
    var followDefault = !cur || sameSp(cur, last) || sameSp(cur, next);

    if (needQa && parseNum(qa && qa.value) == null) {
      tot.value = '';
      tot.setAttribute('data-sanan-sp-suggested', '');
      return;
    }
    if (formula !== 'manual' && followDefault) tot.value = next;
    tot.setAttribute('data-sanan-sp-suggested', next);
  }

  function hideNativeSpFields(root) {
    var m = meta(root);
    if (!m) return;
    var raw = m.getAttribute('data-cf-ids') || '';
    raw.split(',').forEach(function (id) {
      id = String(id || '').trim();
      if (!id) return;
      var el = root.querySelector('#issue_custom_field_values_' + id);
      if (!el || el.closest('.sanan-sp-form') || el.closest('.sanan-sprint-done-form')) return;
      var wrap = el.closest('p') || el.parentElement;
      if (wrap) wrap.style.display = 'none';
    });
  }

  function sprintVisible(root) {
    var box = root.querySelector('#sanan-sp-sprint-form');
    var sel = root.querySelector('#issue_fixed_version_id');
    if (!box) return false;
    if (!sel) return !box.hidden;
    var v = sel.value;
    if (!v) return false;
    var backlogVid = box.getAttribute('data-backlog-version-id') || '';
    if (backlogVid && String(v) === String(backlogVid)) return false;
    return true;
  }

  function syncSprintBox(root) {
    var box = root.querySelector('#sanan-sp-sprint-form');
    if (!box) return;
    box.hidden = !sprintVisible(root);
  }

  function initIssueSpForm(root) {
    root = root || d;
    hideNativeSpFields(root);
    syncSprintBox(root);
    refreshGroup(root, 'size');
    refreshGroup(root, 'sprint');
  }

  w.SANAN_initIssueSpForm = initIssueSpForm;

  d.addEventListener('DOMContentLoaded', function () {
    initIssueSpForm(d);
  });
  if (d.readyState !== 'loading') initIssueSpForm(d);

  d.addEventListener('change', function (e) {
    var t = e.target;
    if (!t) return;
    if (t.id === 'issue_fixed_version_id') {
      initIssueSpForm(t.closest('#issue-form') || t.closest('#global-modal') || d);
      return;
    }
    var role = t.getAttribute && t.getAttribute('data-sanan-sp-role');
    var group = t.getAttribute && t.getAttribute('data-sanan-sp-group');
    if (!group || (role !== 'be' && role !== 'fe' && role !== 'qa')) return;
    refreshGroup(t.closest('#issue-form') || t.closest('#global-modal') || d, group);
  });
})(window, document);
