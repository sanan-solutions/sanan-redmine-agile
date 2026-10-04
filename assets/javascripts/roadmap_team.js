(function ($) {
  'use strict';

  // Product Roadmap — Team & Capacity section.
  var R = window.SananRoadmap = window.SananRoadmap || {};

  R.capacityPills = function (cap) {
    return '<span class="rm-pill">' + R.esc(R.t.team_velocity) + ': <b>' + R.fmtSp(cap.velocity) + '</b> SP/sprint</span>' +
      '<span class="rm-pill">' + R.esc(R.t.team_member_total) + ': <b>' + R.fmtSp(cap.member_total) + '</b> SP/sprint</span>' +
      '<span class="rm-pill">' + R.esc(R.fmt(R.t.team_sprint_days, { days: cap.sprint_days })) + '</span>';
  };

  // user id -> names of the shown products the user belongs to (portfolio: shared people).
  R.membershipIndex = function () {
    var idx = {};
    R.data.products.forEach(function (p) {
      ((p.capacity && p.capacity.members) || []).forEach(function (m) {
        (idx[m.id] = idx[m.id] || []).push(p.name);
      });
    });
    return idx;
  };

  R.memberGrid = function (cap, product, shared) {
    var groups = [], byRole = {};
    (cap.members || []).forEach(function (m) {
      var role = m.role || R.t.team_no_role;
      if (!byRole[role]) { byRole[role] = []; groups.push(role); }
      byRole[role].push(m);
    });
    if (!groups.length) return '<div class="rm-empty">' + R.esc(R.t.team_empty) + '</div>';
    return groups.map(function (role) {
      return '<div class="rm-team__group">' +
        '<div class="rm-team__role">' + R.esc(role) + ' <span class="rm-small">(' + byRole[role].length + ')</span></div>' +
        '<div class="rm-team__members">' + byRole[role].map(function (m) {
          var hasData = m.avg_sp !== null && m.avg_sp !== undefined;
          var others = shared && product ? (shared[m.id] || []).filter(function (n) { return n !== product.name; }) : [];
          return '<div class="rm-member' + (hasData ? '' : ' is-empty') + (others.length ? ' is-shared' : '') + '"' +
            (others.length ? ' title="' + R.esc(R.fmt(R.t.team_shared_tip, { products: others.join(', ') })) + '"' : '') + '>' +
            '<span class="rm-avatar">' + R.esc(m.initials) + '</span>' +
            '<div class="rm-member__info">' +
              '<div class="rm-member__name">' + R.esc(m.name) + '</div>' +
              '<div class="rm-small">' + (hasData
                ? '<b class="rm-strong">' + R.fmtSp(m.avg_sp) + '</b> ' + R.esc(R.t.team_per_sprint) + ' · ' +
                  R.esc(R.fmt(R.t.team_active, { n: m.sprints_active, window: cap.sample_size }))
                : R.esc(R.t.team_no_data)) +
              '</div>' +
              (others.length ? '<div class="rm-member__shared">' + R.esc(R.fmt(R.t.team_shared, { products: others.join(', ') })) + '</div>' : '') +
            '</div>' +
          '</div>';
        }).join('') + '</div>' +
      '</div>';
    }).join('');
  };

  // Team & Capacity: one block per product (members by role, avg SP per sprint over the window).
  R.renderTeam = function () {
    var withCap = R.data.products.filter(function (p) { return p.capacity; });
    $('#rm-team').prop('hidden', withCap.length === 0);
    if (!withCap.length) return;

    var first = withCap[0].capacity;
    var shared = withCap.length > 1 ? R.membershipIndex() : null;
    var summary = '<b>' + R.esc(R.t.team_title) + '</b>' +
      '<span class="rm-info" title="' + R.esc(R.t.team_hint) + '">ⓘ</span>';
    if (withCap.length === 1) {
      summary += '<span class="rm-small">' + R.esc(R.fmt(R.t.team_window, { n: first.sample_size, window: first.window })) + '</span>' +
        R.capacityPills(first);
    } else {
      var total = withCap.reduce(function (s, p) { return s + (Number(p.capacity.velocity) || 0); }, 0);
      summary += '<span class="rm-pill">' + R.esc(R.t.team_velocity) + ' (' + withCap.length + ' ' + R.esc(R.t.products) + '): <b>' +
        R.fmtSp(total) + '</b> SP/sprint</span>';
      var sharedCount = Object.keys(shared).filter(function (id) { return shared[id].length > 1; }).length;
      if (sharedCount) {
        summary += '<span class="rm-pill rm-pill--warn" title="' + R.esc(R.t.team_shared_hint) + '">' +
          R.esc(R.fmt(R.t.team_shared_count, { n: sharedCount })) + '</span>';
      }
    }
    $('#rm-team-summary').html(summary);

    var body = withCap.map(function (p) {
      if (withCap.length === 1) return R.memberGrid(p.capacity);
      return '<div class="rm-team__product">' +
        '<div class="rm-team__product-head"><b>' + R.esc(p.name) + '</b>' +
          '<span class="rm-small">' + R.esc(R.fmt(R.t.team_window, { n: p.capacity.sample_size, window: p.capacity.window })) + '</span>' +
          R.capacityPills(p.capacity) +
        '</div>' +
        R.memberGrid(p.capacity, p, shared) +
      '</div>';
    }).join('');
    $('#rm-team-body').html(body);
  };
})(jQuery);
