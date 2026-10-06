(function () {
  function initSananSettingsTabs() {
    var root = document.getElementById('sanan-settings');
    if (!root || root.getAttribute('data-sa-tabs-ready') === '1') return;
    root.setAttribute('data-sa-tabs-ready', '1');

    var tabs = root.querySelectorAll('[data-sa-tab]');
    var panels = root.querySelectorAll('[data-sa-panel]');
    if (!tabs.length || !panels.length) return;

    function activate(id, pushHash) {
      var found = false;
      for (var i = 0; i < panels.length; i++) {
        var panel = panels[i];
        var on = panel.getAttribute('data-sa-panel') === id;
        panel.hidden = !on;
        panel.classList.toggle('is-active', on);
        if (on) found = true;
      }
      if (!found) {
        activate(panels[0].getAttribute('data-sa-panel'), false);
        return;
      }
      for (var j = 0; j < tabs.length; j++) {
        var tab = tabs[j];
        var selected = tab.getAttribute('data-sa-tab') === id;
        tab.classList.toggle('is-active', selected);
        tab.setAttribute('aria-selected', selected ? 'true' : 'false');
      }
      try {
        localStorage.setItem('sanan-settings-tab', id);
      } catch (e) {}
      if (pushHash && window.history && window.history.replaceState) {
        window.history.replaceState(null, '', '#' + id);
      }
    }

    for (var k = 0; k < tabs.length; k++) {
      tabs[k].addEventListener('click', function (e) {
        e.preventDefault();
        activate(this.getAttribute('data-sa-tab'), true);
      });
    }

    var fromHash = (window.location.hash || '').replace(/^#/, '');
    var fromStore = null;
    try {
      fromStore = localStorage.getItem('sanan-settings-tab');
    } catch (e2) {}
    var initial = fromHash || fromStore || 'sa-general';
    activate(initial, false);
  }

  // Project settings: tag the fields that follow the global settings (not stored for the project).
  function markInherited() {
    var root = document.getElementById('sanan-settings');
    if (!root) return;
    var keys = (root.getAttribute('data-inherited-keys') || '').split(',').filter(Boolean);
    if (!keys.length) return;
    var label = root.getAttribute('data-inherited-label') || 'global';
    keys.forEach(function (key) {
      var input = root.querySelector('[name="settings[' + key + ']"]:not([type="hidden"]), [name="settings[' + key + '][]"]:not([type="hidden"])');
      if (!input) return;
      var row = input.closest('p, tr, label');
      var title = row && (row.querySelector(':scope > label') || row.querySelector('th, label'));
      if (!title || title.querySelector('.sanan-settings__inherited')) return;
      var tag = document.createElement('span');
      tag.className = 'sanan-settings__inherited';
      tag.textContent = label;
      title.appendChild(tag);
    });
  }

  function boot() {
    initSananSettingsTabs();
    markInherited();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
