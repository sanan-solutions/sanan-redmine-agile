/* Inline editing on the Issues list: a pencil on hover (or a double-click) turns a cell into an editor; the
 * value is saved through the plugin endpoint (permissions / workflow as in the issue form) and the cell is
 * re-rendered as the list shows it. Config: window.SA_INLINE_EDIT (lib/sanan_agile/assets_hook.rb). */
(function (w, $) {
  'use strict';
  if (!$) return;

  var CORE = ['subject', 'tracker', 'status', 'priority', 'assigned_to', 'category', 'fixed_version',
    'start_date', 'due_date', 'done_ratio', 'estimated_hours'];
  var cfg = null;
  var active = null; // { $td, field, issueId, html }

  function t(key) { return (cfg.labels && cfg.labels[key]) || key; }

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function csrf() { return $('meta[name="csrf-token"]').attr('content') || ''; }

  function url(issueId, field) {
    return cfg.urlTemplate.replace('__ID__', encodeURIComponent(issueId)).replace('__FIELD__', encodeURIComponent(field));
  }

  // Query column of a list cell: its first class (td class="status", "cf_12 list", "due_date"…).
  function fieldOf(td) {
    var name = (td.className || '').split(/\s+/)[0];
    if (!name) return null;
    if (CORE.indexOf(name) !== -1 || /^cf_\d+$/.test(name)) return name;
    return null;
  }

  function issueIdOf(td) {
    var tr = td.closest('tr.issue');
    var m = tr && /^issue-(\d+)$/.exec(tr.id || '');
    return m ? m[1] : null;
  }

  function editableCell(td) {
    return td && !td.classList.contains('sa-ie-noedit') && fieldOf(td) && issueIdOf(td);
  }

  // ----- pencil --------------------------------------------------------------------------------------------

  function showPencil(td) {
    if (!editableCell(td) || td.querySelector('.sa-ie-pencil') || td.classList.contains('sa-ie-editing')) return;
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'sa-ie-pencil';
    btn.title = t('edit');
    btn.setAttribute('aria-label', t('edit'));
    btn.innerHTML = '<svg width="12" height="12" viewBox="0 0 16 16" aria-hidden="true"><path fill="currentColor" ' +
      'd="M11.7 1.3a1 1 0 0 1 1.4 0l1.6 1.6a1 1 0 0 1 0 1.4l-8.5 8.5-3.4.9.9-3.4 8-9z"/></svg>';
    td.classList.add('sa-ie-cell');
    td.appendChild(btn);
  }

  function hidePencil(td) {
    var btn = td && td.querySelector('.sa-ie-pencil');
    if (btn) btn.remove();
  }

  // ----- editor --------------------------------------------------------------------------------------------

  function control(ed) {
    var value = ed.value == null ? '' : String(ed.value);
    if (ed.type === 'select') {
      var opts = (ed.allow_blank || value === '' ? '<option value="">' + esc(t('none')) + '</option>' : '') +
        (ed.options || []).map(function (o) {
          return '<option value="' + esc(o[1]) + '"' + (String(o[1]) === value ? ' selected' : '') + '>' + esc(o[0]) + '</option>';
        }).join('');
      return '<select class="sa-ie-input">' + opts + '</select>';
    }
    var type = ed.type === 'date' ? 'date' : (ed.type === 'number' ? 'number' : 'text');
    return '<input type="' + type + '" class="sa-ie-input"' + (type === 'number' ? ' step="any"' : '') +
      ' value="' + esc(value) + '">';
  }

  function open(td) {
    if (!editableCell(td)) return;
    if (active) cancel();
    var field = fieldOf(td);
    var issueId = issueIdOf(td);
    hidePencil(td);
    td.classList.add('sa-ie-loading');
    $.getJSON(url(issueId, field)).done(function (ed) {
      td.classList.remove('sa-ie-loading');
      active = { td: td, field: field, issueId: issueId, html: td.innerHTML, ed: ed };
      td.classList.add('sa-ie-editing');
      td.innerHTML = '<span class="sa-ie-editor">' + control(ed) + '</span>';
      var input = td.querySelector('.sa-ie-input');
      input.focus();
      if (input.select && input.tagName === 'INPUT' && input.type === 'text') input.select();
    }).fail(function (xhr) {
      td.classList.remove('sa-ie-loading');
      td.classList.add('sa-ie-noedit');
      var body = xhr.responseJSON || {};
      flashError(td, body.error || t('notEditable'));
    });
  }

  function cancel() {
    if (!active) return;
    var a = active;
    active = null;
    a.td.classList.remove('sa-ie-editing');
    a.td.innerHTML = a.html;
    hidePencil(a.td);
  }

  function save() {
    if (!active || active.saving) return;
    var a = active;
    var input = a.td.querySelector('.sa-ie-input');
    var value = input ? input.value : '';
    if (String(value) === String(a.ed.value == null ? '' : a.ed.value)) { cancel(); return; }
    a.saving = true;
    a.td.classList.add('sa-ie-loading');
    $.ajax({
      url: url(a.issueId, a.field),
      type: 'PATCH',
      dataType: 'json',
      headers: { 'X-CSRF-Token': csrf() },
      data: { value: value, lock_version: a.ed.lock_version }
    }).done(function (res) {
      active = null;
      a.td.classList.remove('sa-ie-editing', 'sa-ie-loading');
      a.td.innerHTML = res.html;
      var tr = a.td.closest('tr.issue');
      // Cells the save changed too (e.g. the SP Total derived from the part just edited).
      Object.keys(res.cells || {}).forEach(function (f) {
        var other = tr && tr.querySelector('td.' + f);
        if (!other || other === a.td || other.classList.contains('sa-ie-editing')) return;
        if (other.innerHTML !== res.cells[f]) {
          other.innerHTML = res.cells[f];
          other.classList.add('sa-ie-saved');
          setTimeout(function () { other.classList.remove('sa-ie-saved'); }, 1200);
        }
      });
      if (tr) tr.classList.toggle('closed', !!res.closed);
      a.td.classList.add('sa-ie-saved');
      setTimeout(function () { a.td.classList.remove('sa-ie-saved'); }, 1200);
    }).fail(function (xhr) {
      a.saving = false;
      a.td.classList.remove('sa-ie-loading');
      var body = xhr.responseJSON || {};
      var msg = (body.errors && body.errors.length ? body.errors : [t('failed')]).join('\n');
      if (body.stale) { cancel(); flashError(a.td, msg); return; }
      flashError(a.td, msg);
      var again = a.td.querySelector('.sa-ie-input');
      if (again) again.focus();
    });
  }

  var $tip = null;
  function flashError(td, message) {
    if (!$tip) $tip = $('<div class="sa-ie-error" role="alert"></div>').appendTo('body');
    var r = td.getBoundingClientRect();
    $tip.text(message).css({ left: Math.max(8, r.left), top: r.bottom + 4 }).show();
    clearTimeout(flashError.timer);
    flashError.timer = setTimeout(function () { $tip.hide(); }, 4000);
  }

  function restoreSelection(tr, selected) {
    var $tr = $(tr);
    if (tr.classList.contains('context-menu-selection') === selected) return;
    if (selected && typeof w.contextMenuAddSelection === 'function') w.contextMenuAddSelection($tr);
    else if (!selected && typeof w.contextMenuRemoveSelection === 'function') w.contextMenuRemoveSelection($tr);
  }

  // ----- events --------------------------------------------------------------------------------------------

  function bind() {
    var $doc = $(document);
    $doc.on('mouseenter', 'table.list.issues tr.issue > td', function () { showPencil(this); });
    $doc.on('mouseleave', 'table.list.issues tr.issue > td', function () { hidePencil(this); });
    // Keep row selection / context menu out of the pencil and the editor.
    $doc.on('mousedown click', '.sa-ie-pencil, .sa-ie-editor', function (e) { e.stopPropagation(); });
    $doc.on('click', '.sa-ie-pencil', function (e) {
      e.preventDefault();
      open(this.closest('td'));
    });
    // A double-click is two clicks, which Redmine uses to (un)select the row: remember the selection the
    // row had before the double-click started and put it back.
    var lastDown = 0;
    $doc.on('mousedown', 'table.list.issues tr.issue > td', function () {
      var now = Date.now();
      var tr = this.closest('tr.issue');
      if (tr && now - lastDown > 500) tr.dataset.saSelBefore = tr.classList.contains('context-menu-selection') ? '1' : '0';
      lastDown = now;
    });
    $doc.on('dblclick', 'table.list.issues tr.issue > td', function (e) {
      if ($(e.target).closest('a, .sa-ie-editor').length) return; // links keep their own behaviour
      e.preventDefault();
      var tr = this.closest('tr.issue');
      if (tr && tr.dataset.saSelBefore) restoreSelection(tr, tr.dataset.saSelBefore === '1');
      if (w.getSelection) w.getSelection().removeAllRanges();
      open(this);
    });
    $doc.on('change', '.sa-ie-editor select', save);
    $doc.on('keydown', '.sa-ie-editor .sa-ie-input', function (e) {
      if (e.key === 'Enter') { e.preventDefault(); save(); }
      if (e.key === 'Escape') { e.preventDefault(); cancel(); }
    });
    $doc.on('blur', '.sa-ie-editor input.sa-ie-input', function () { setTimeout(save, 0); });
    $doc.on('mousedown', function (e) {
      if (active && !$(e.target).closest('.sa-ie-editor').length) {
        if (active.td.querySelector('select.sa-ie-input')) cancel();
      }
    });
  }

  $(function () {
    cfg = w.SA_INLINE_EDIT;
    if (!cfg || !cfg.urlTemplate || !document.querySelector('table.list.issues')) return;
    bind();
  });
})(window, window.jQuery);
