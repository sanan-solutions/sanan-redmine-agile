(function ($) {
  'use strict';

  // Product Roadmap — boot. Modules: roadmap_core, roadmap_board, roadmap_team, roadmap_detail, roadmap_actions.
  var R = window.SananRoadmap = window.SananRoadmap || {};

  $(function () {
    R.$root = $('#sanan-roadmap');
    if (!R.$root.length) return;
    R.setData(R.readJson('roadmap-data'));
    R.t = R.readJson('roadmap-i18n');
    R.state = { status: '', health: '', q: '', owner: '', selected: null, review: null, backlog: false, pendingEpic: null };

    R.bindEvents();
    try {
      var view = window.localStorage.getItem('sananRoadmapView');
      if (view === 'detailed' || view === 'timeline') R.$root.addClass(view === 'timeline' ? 'is-timeline' : '')
        .removeClass('is-compact').find('[data-rm-view]').removeClass('is-active').filter('[data-rm-view="' + view + '"]').addClass('is-active');
    } catch (err) { /* ignore */ }
    R.renderBoard();
    R.renderAll();
  });
})(jQuery);
