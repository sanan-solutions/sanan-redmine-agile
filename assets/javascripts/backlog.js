(function ($) {
  'use strict';

  function csrfToken() {
    return $('meta[name="csrf-token"]').attr('content') ||
      $('input[name="authenticity_token"]').val();
  }

  function buildPositions($list) {
    var positions = {};
    $list.find('tr.backlog-row').each(function (i) {
      var id = $(this).attr('data-id') || $(this).data('id');
      if (id) positions[String(id)] = { position: i };
    });
    return positions;
  }

  function versionIdOf($list) {
    var v = $list.attr('data-version-id');
    return v === undefined || v === null || v === '' ? null : v;
  }

  function removeEmptyPlaceholders($list) {
    $list.find('tr.backlog-empty-row').remove();
  }

  function ensureEmptyPlaceholder($list) {
    if ($list.find('tr.backlog-row').length === 0 && $list.find('tr.backlog-empty-row').length === 0) {
      var cols = $list.closest('table').find('thead th').length || 10;
      $list.append(
        '<tr class="backlog-empty-row"><td colspan="' + cols + '" class="nodata">' +
          ($('#sanan-backlog').attr('data-empty-label') || 'No data') +
        '</td></tr>'
      );
    }
  }

  function updateBulkBar() {
    var $checks = $('.backlog-row-check');
    var $checked = $checks.filter(':checked');
    var n = $checked.length;
    var $bar = $('#backlog-bulk-bar');
    var $root = $('#sanan-backlog');
    if (!$bar.length) return;

    $('#backlog-bulk-count').text(n);
    if (n > 0) {
      $bar.prop('hidden', false);
      $root.addClass('has-bulk-selection');
    } else {
      $bar.prop('hidden', true);
      $root.removeClass('has-bulk-selection');
    }

    $checks.each(function () {
      $(this).closest('tr.backlog-row').toggleClass('is-selected', this.checked);
    });

    var allChecked = $checks.length > 0 && n === $checks.length;
    $('.backlog-select-all').prop('checked', allChecked);
  }

  function clearBulkSelection() {
    $('.backlog-row-check, .backlog-select-all').prop('checked', false);
    updateBulkBar();
  }

  function selectAllVisible() {
    $('.backlog-row-check').prop('checked', true);
    updateBulkBar();
  }

  function initBulk() {
    $(document).on('change', '.backlog-row-check', updateBulkBar);
    $(document).on('change', '.backlog-select-all', function () {
      var on = $(this).prop('checked');
      // Select across all sections when using floating bar UX
      $('.backlog-row-check').prop('checked', on);
      updateBulkBar();
    });
    $(document).on('click', '#backlog-bulk-select-all', function (e) {
      e.preventDefault();
      selectAllVisible();
    });
    $(document).on('click', '#backlog-bulk-clear', function (e) {
      e.preventDefault();
      clearBulkSelection();
    });
    $(document).on('click', '#backlog-bulk-form input[type=submit]', function (e) {
      var $btn = $(this);
      var action = ($btn.attr('formaction') || '').toString();
      if (action.indexOf('bulk_update_status') >= 0) {
        var statusId = $('#backlog-bulk-form select[name=status_id]').val();
        if (!statusId) {
          e.preventDefault();
          window.alert('Please choose a status.');
          return false;
        }
      }
      if (action.indexOf('attach_to_release') >= 0) {
        var releaseId = $('#backlog-bulk-form select[name=release_id]').val();
        if (!releaseId) {
          e.preventDefault();
          window.alert('Please choose a release.');
          return false;
        }
      }
      if (action.indexOf('bulk_destroy') >= 0) {
        var msg = $btn.attr('data-confirm') ||
          $btn.data('confirm') ||
          'Delete selected issues permanently?';
        if (!window.confirm(String(msg))) {
          e.preventDefault();
          e.stopImmediatePropagation();
          return false;
        }
      }
    });
  }

  // Use attr — jQuery .data() coerces data-can-manage="1" to number 1
  function canManage($root) {
    return String($root.attr('data-can-manage')) === '1';
  }

  function initSortable() {
    var $root = $('#sanan-backlog');
    if (!$root.length || !canManage($root)) return;
    if (!$.fn.sortable) {
      if (window.console && console.warn) {
        console.warn('[sanan-backlog] jQuery UI Sortable missing — drag & drop disabled');
      }
      return;
    }

    var url = $root.attr('data-reorder-url');
    var $lists = $root.find('.backlog-section-list');

    $lists.sortable({
      items: 'tr.backlog-row',
      handle: '.backlog-drag-handle',
      connectWith: '.backlog-section-list',
      placeholder: 'backlog-placeholder',
      distance: 4,
      tolerance: 'pointer',
      cancel: 'input, textarea, button, select',
      helper: function (e, tr) {
        var $originals = tr.children();
        var $helper = tr.clone();
        $helper.children().each(function (index) {
          $(this).width($originals.eq(index).outerWidth());
        });
        return $('<table class="list backlog-table backlog-drag-helper"/>').append($helper);
      },
      start: function (e, ui) {
        ui.placeholder.html(
          '<td colspan="' + ui.item.children().length + '">&nbsp;</td>'
        );
        ui.placeholder.height(ui.item.outerHeight());
        removeEmptyPlaceholders(ui.item.closest('.backlog-section-list'));
        $root.addClass('is-dragging');
      },
      receive: function () {
        removeEmptyPlaceholders($(this));
      },
      stop: function (e, ui) {
        $root.removeClass('is-dragging');
        var $item = ui.item;
        var $list = $item.closest('.backlog-section-list');
        var issueId = $item.attr('data-id') || $item.data('id');
        var toVersionId = versionIdOf($list);
        var positions = buildPositions($list);

        $lists.each(function () {
          ensureEmptyPlaceholder($(this));
        });

        $.ajax({
          url: url,
          type: 'PATCH',
          dataType: 'json',
          headers: {
            'X-CSRF-Token': csrfToken(),
            'X-Requested-With': 'XMLHttpRequest'
          },
          data: {
            issue_id: issueId,
            to_version_id: toVersionId,
            positions: positions
          }
        }).fail(function (xhr) {
          window.alert('Backlog reorder failed: ' + (xhr.responseJSON && xhr.responseJSON.error ? xhr.responseJSON.error : xhr.status));
          window.location.reload();
        });
      }
    }).disableSelection();
  }

  $(document).ready(function () {
    initSortable();
    initBulk();
    initCompleteSprintModal();
    initEpicPanel();
    initSectionCollapse();
    initStickyFilters();
    initCreateSprintModal();
    initInlineEdit();
  });

  function initInlineEdit() {
    var $root = $('#sanan-backlog');
    if (!$root.length || $root.attr('data-can-manage') !== '1') return;

    var url = $root.attr('data-quick-update-url');
    if (!url) return;

    var options = {};
    try {
      options = JSON.parse($('#backlog-edit-options').text() || '{}');
    } catch (e) {
      options = {};
    }

    var optionKeyByType = {
      tracker: 'trackers',
      priority: 'priorities',
      status: 'statuses',
      assignee: 'assignees',
      epic: 'epics',
      release: 'releases'
    };

    var outsideNs = 'mousedown.backlogInlineEdit';

    function unbindOutside() {
      $(document).off(outsideNs);
    }

    function unbindMenuFollow($cell) {
      var fn = $cell.data('backlogFollow');
      if (!fn) return;
      document.removeEventListener('scroll', fn, true);
      window.removeEventListener('resize', fn);
      $cell.removeData('backlogFollow');
    }

    function closeEditor($cell, restore) {
      var $input = $cell.data('backlogEditor');
      unbindOutside();
      unbindMenuFollow($cell);
      $(document).off('keydown.backlogInlineEditEsc');
      if ($input && $input.length) $input.remove();
      if (restore) $cell.find('.backlog-cell-edit__display').show();
      $cell.removeData('backlogEditor');
      $cell.removeClass('is-editing');
    }

    function optionListFor(field, type) {
      var key = optionKeyByType[type];
      if (field === 'tracker_id') key = 'trackers';
      else if (field === 'priority_id') key = 'priorities';
      else if (field === 'status_id') key = 'statuses';
      else if (field === 'assigned_to_id') key = 'assignees';
      else if (field === 'parent_id' || field === 'epic_id') key = 'epics';
      else if (field === 'release_id') key = 'releases';
      return options[key] || [];
    }

    function updateMenuPosition($menu, $cell) {
      var rect = $cell[0].getBoundingClientRect();
      var width = Math.max(rect.width, 168);
      var maxH = 260;
      var top = rect.bottom + 4;
      if (top + Math.min(maxH, 160) > window.innerHeight - 8) {
        top = Math.max(8, rect.top - Math.min(maxH, 200) - 4);
      }
      var left = Math.min(Math.max(8, rect.left), window.innerWidth - width - 8);
      $menu.css({
        position: 'fixed',
        left: left + 'px',
        top: top + 'px',
        width: width + 'px',
        maxHeight: maxH + 'px',
        zIndex: 4000
      });
    }

    function placeMenu($menu, $cell) {
      updateMenuPosition($menu, $cell);
      if (!$menu.parent().is('body')) $('body').append($menu);
    }

    function bindMenuFollow($cell, $menu) {
      unbindMenuFollow($cell);
      function onScrollOrResize() {
        if (!$cell.hasClass('is-editing') || !$menu.closest('body').length) return;
        var rect = $cell[0].getBoundingClientRect();
        // Close if the anchor cell left the viewport
        if (rect.bottom < 8 || rect.top > window.innerHeight - 8) {
          closeEditor($cell, true);
          return;
        }
        updateMenuPosition($menu, $cell);
      }
      $cell.data('backlogFollow', onScrollOrResize);
      document.addEventListener('scroll', onScrollOrResize, true);
      window.addEventListener('resize', onScrollOrResize);
    }

    function buildMenu(list, current) {
      var $menu = $('<div class="backlog-cell-menu" role="listbox" tabindex="-1" />');
      (list || []).forEach(function (opt) {
        var selected = String(opt.id) === String(current);
        var $item = $('<div class="backlog-cell-menu__item" role="option" tabindex="0" />')
          .attr('data-value', String(opt.id))
          .attr('aria-selected', selected ? 'true' : 'false')
          .text(opt.name);
        if (selected) $item.addClass('is-selected');
        $menu.append($item);
      });
      return $menu;
    }

    function save($cell, value) {
      var issueId = $cell.closest('tr.backlog-row').attr('data-id');
      var field = $cell.attr('data-field');
      if (!issueId || !field) return;

      $cell.addClass('is-saving');
      $.ajax({
        url: url,
        method: 'POST',
        dataType: 'json',
        headers: { 'X-CSRF-Token': csrfToken() },
        data: {
          issue_id: issueId,
          field: field,
          value: value
        }
      }).done(function (res) {
        if (!res || !res.ok) {
          window.alert((res && res.error) || 'Update failed');
          closeEditor($cell, true);
          return;
        }
        var display = res.display || {};
        var $disp = $cell.find('.backlog-cell-edit__display');
        if (display.html != null && display.html !== '') {
          $disp.html(display.html);
        } else if (display.text != null) {
          $disp.text(display.text);
        }
        if (display.id != null) $cell.attr('data-value', display.id);
        else if (display.text != null && field === 'subject') $cell.attr('data-value', display.text);
        else if (field === 'story_points') $cell.attr('data-value', display.text || value);
        else $cell.attr('data-value', value);

        if (field === 'subject' && $disp.is('a')) {
          $disp.attr('href', '/issues/' + issueId);
        }
        closeEditor($cell, false);
        $disp.show();
        $cell.addClass('backlog-cell-edit--flash');
        setTimeout(function () { $cell.removeClass('backlog-cell-edit--flash'); }, 800);
      }).fail(function (xhr) {
        var msg = 'Update failed';
        try {
          var body = JSON.parse(xhr.responseText);
          if (body && body.error) msg = body.error;
        } catch (err) {}
        window.alert(msg);
        closeEditor($cell, true);
      }).always(function () {
        $cell.removeClass('is-saving');
      });
    }

    function bindOutsideClose($cell, $input) {
      unbindOutside();
      setTimeout(function () {
        $(document).on(outsideNs, function (e) {
          var $t = $(e.target);
          if ($t.closest($cell).length || $t.closest($input).length) return;
          closeEditor($cell, true);
        });
      }, 0);
    }

    function openEditor($cell) {
      if ($cell.hasClass('is-editing') || $cell.hasClass('is-saving')) return;
      $('.backlog-cell-edit.is-editing').each(function () {
        closeEditor($(this), true);
      });

      var type = $cell.attr('data-edit-type') || 'select';
      var field = $cell.attr('data-field');
      var current = $cell.attr('data-value');
      var $disp = $cell.find('.backlog-cell-edit__display');
      var $input;

      if (type === 'text' || type === 'sp') {
        $input = $('<input class="backlog-cell-edit__input" />');
        if (type === 'sp') $input.attr({ type: 'number', step: '0.5', min: '0' });
        else $input.attr({ type: 'text' });
        $input.val(current || $disp.text());
        $cell.append($input);
      } else {
        $input = buildMenu(optionListFor(field, type), current);
        placeMenu($input, $cell);
        $cell.addClass('is-editing');
        $cell.data('backlogEditor', $input);
        bindOutsideClose($cell, $input);
        bindMenuFollow($cell, $input);
        $input.on('click', '.backlog-cell-menu__item', function (e) {
          e.preventDefault();
          e.stopPropagation();
          var v = $(this).attr('data-value');
          if (String(v) === String(current)) {
            closeEditor($cell, true);
            return;
          }
          save($cell, v);
        });
        $(document).on('keydown.backlogInlineEditEsc', function (e) {
          if (e.key === 'Escape') {
            e.preventDefault();
            closeEditor($cell, true);
          }
        });
        var $selected = $input.find('.is-selected');
        if ($selected.length) {
          var menuEl = $input[0];
          menuEl.scrollTop = Math.max(0, $selected[0].offsetTop - 40);
        }
        return;
      }

      $cell.addClass('is-editing');
      $cell.data('backlogEditor', $input);
      $disp.hide();
      $input.trigger('focus').trigger('select');
      bindOutsideClose($cell, $input);

      $input.on('keydown', function (e) {
        if (e.key === 'Escape') {
          e.preventDefault();
          closeEditor($cell, true);
        } else if (e.key === 'Enter') {
          e.preventDefault();
          save($cell, $input.val());
        }
      });

      $input.on('blur', function () {
        setTimeout(function () {
          if (!$cell.hasClass('is-editing') || $cell.hasClass('is-saving')) return;
          var next = $input.val();
          var prev = $cell.attr('data-value') || '';
          if (String(next) === String(prev)) closeEditor($cell, true);
          else save($cell, next);
        }, 150);
      });
    }

    $root.on('click', 'td.backlog-cell-edit', function (e) {
      var $cell = $(this);
      if ($cell.attr('data-field') === 'subject') return; // dblclick only
      if ($(e.target).closest('a.backlog-issue-link').length) return;
      if ($cell.hasClass('is-editing')) {
        e.preventDefault();
        e.stopPropagation();
        closeEditor($cell, true);
        return;
      }
      e.preventDefault();
      e.stopPropagation();
      openEditor($cell);
    });

    $root.on('dblclick', 'td.subject.backlog-cell-edit', function (e) {
      e.preventDefault();
      e.stopPropagation();
      openEditor($(this));
    });
  }

  function initCreateSprintModal() {
    var $modal = $('#backlog-create-sprint-modal');
    if (!$modal.length) return;

    var $hint = $('#backlog-create-sprint-selected-hint');
    var $ids = $('#backlog-create-sprint-issue-ids');
    var $list = $('#backlog-create-sprint-issue-list');
    var $empty = $('#backlog-create-sprint-issues-empty');
    var noneTpl = $modal.attr('data-none-selected') || '';
    var someTpl = $modal.attr('data-selected-template') || '';
    var removeLabel = $modal.attr('data-remove-label') || 'Remove';
    var selectedIssues = [];

    function escapeHtml(str) {
      return String(str == null ? '' : str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
    }

    function collectSelectedFromPage() {
      var items = [];
      $('.backlog-row-check:checked').each(function () {
        var $row = $(this).closest('tr.backlog-row');
        var id = String(this.value);
        items.push({
          id: id,
          subject: $.trim($row.find('.backlog-issue-subject').text()) || ('#' + id),
          tracker: $.trim($row.find('td.tracker').text()) || ''
        });
      });
      return items;
    }

    function syncHiddenIds() {
      $ids.empty();
      selectedIssues.forEach(function (item) {
        $ids.append(
          $('<input>', { type: 'hidden', name: 'issue_ids[]', value: item.id })
        );
      });
    }

    function syncHint() {
      var n = selectedIssues.length;
      if (n > 0) {
        $hint.text(someTpl.replace('__COUNT__', String(n)));
      } else {
        $hint.text(noneTpl);
      }
    }

    function renderIssueList() {
      $list.empty();
      if (!selectedIssues.length) {
        $empty.prop('hidden', false);
        $list.prop('hidden', true);
        syncHiddenIds();
        syncHint();
        return;
      }

      $empty.prop('hidden', true);
      $list.prop('hidden', false);
      selectedIssues.forEach(function (item) {
        var meta = item.tracker ? (escapeHtml(item.tracker) + ' · ') : '';
        var $li = $(
          '<li class="backlog-modal__issue-item">' +
            '<div class="backlog-modal__issue-main">' +
              '<span class="backlog-modal__issue-id">#' + escapeHtml(item.id) + '</span>' +
              '<span class="backlog-modal__issue-meta">' + meta + escapeHtml(item.subject) + '</span>' +
            '</div>' +
            '<span class="backlog-modal__issue-remove" role="button" tabindex="0" data-issue-id="' + escapeHtml(item.id) + '" title="' + escapeHtml(removeLabel) + '" aria-label="' + escapeHtml(removeLabel) + '">' +
              '<svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true" focusable="false">' +
                '<path d="M3.2 3.2l7.6 7.6M10.8 3.2l-7.6 7.6" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/>' +
              '</svg>' +
            '</span>' +
          '</li>'
        );
        $list.append($li);
      });
      syncHiddenIds();
      syncHint();
    }

    function removeIssue(id) {
      selectedIssues = selectedIssues.filter(function (item) {
        return item.id !== String(id);
      });
      var $check = $('.backlog-row-check[value="' + String(id).replace(/"/g, '\\"') + '"]');
      if ($check.length) {
        $check.prop('checked', false).trigger('change');
      }
      renderIssueList();
    }

    function openModal() {
      selectedIssues = collectSelectedFromPage();
      renderIssueList();
      $modal.prop('hidden', false);
      $('body').addClass('backlog-modal-open');
      setTimeout(function () {
        $('#backlog-create-sprint-name').trigger('focus');
      }, 0);
    }

    function closeModal() {
      $modal.prop('hidden', true);
      $('body').removeClass('backlog-modal-open');
    }

    $(document).on('click', '.backlog-create-sprint-open', function (e) {
      e.preventDefault();
      e.stopPropagation();
      openModal();
    });

    $modal.on('click', '[data-create-sprint-dismiss]', function (e) {
      e.preventDefault();
      closeModal();
    });

    $modal.on('click', '.backlog-modal__issue-remove', function (e) {
      e.preventDefault();
      e.stopPropagation();
      removeIssue($(this).attr('data-issue-id'));
    });

    $modal.on('keydown', '.backlog-modal__issue-remove', function (e) {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        e.stopPropagation();
        removeIssue($(this).attr('data-issue-id'));
      }
    });

    $(document).on('keydown.createSprintModal', function (e) {
      if (e.key === 'Escape' && !$modal.prop('hidden')) {
        closeModal();
      }
    });
  }

  function initStickyFilters() {
    var host = document.getElementById('backlog-filters-host');
    var filter = document.getElementById('backlog-filters');
    if (!host || !filter) return;

    var topGap = 8;
    var pinned = false;

    function pin() {
      var rect = host.getBoundingClientRect();
      host.style.height = filter.offsetHeight + 'px';
      filter.classList.add('is-pinned');
      filter.style.left = rect.left + 'px';
      filter.style.width = rect.width + 'px';
      pinned = true;
    }

    function unpin() {
      filter.classList.remove('is-pinned');
      filter.style.left = '';
      filter.style.width = '';
      host.style.height = '';
      pinned = false;
    }

    function sync() {
      var hostTop = host.getBoundingClientRect().top;
      if (hostTop < topGap) {
        if (!pinned) pin();
        else {
          var rect = host.getBoundingClientRect();
          filter.style.left = rect.left + 'px';
          filter.style.width = rect.width + 'px';
        }
      } else if (pinned) {
        unpin();
      }
    }

    window.addEventListener('scroll', sync, { passive: true });
    window.addEventListener('resize', sync);
    // Recalculate after fonts/layout settle
    setTimeout(sync, 0);
    sync();
  }

  function initSectionCollapse() {
    var $root = $('#sanan-backlog');
    if (!$root.length) return;

    var projectId = $root.attr('data-project-id') || '0';

    function storageKey(sectionKey) {
      return 'sanan-backlog-section-' + projectId + '-' + sectionKey;
    }

    function setCollapsed($section, collapsed) {
      var key = $section.attr('data-section-key') || 'unknown';
      $section.toggleClass('is-collapsed', collapsed);
      $section.find('.backlog-section-chevron').attr('aria-expanded', collapsed ? 'false' : 'true');
      try {
        localStorage.setItem(storageKey(key), collapsed ? '1' : '0');
      } catch (err) { /* ignore */ }
    }

    $('.backlog-section').each(function () {
      var $section = $(this);
      var key = $section.attr('data-section-key') || 'unknown';
      var stored = null;
      try {
        stored = localStorage.getItem(storageKey(key));
      } catch (err) {
        stored = null;
      }

      var collapsed;
      if (stored === '1') collapsed = true;
      else if (stored === '0') collapsed = false;
      else collapsed = $section.attr('data-collapse-default') === '1';

      setCollapsed($section, collapsed);
    });

    $(document).on('click', '.backlog-section-header[data-section-toggle]', function (e) {
      if ($(e.target).closest('[data-no-toggle]').length) return;
      e.preventDefault();
      var $section = $(this).closest('.backlog-section');
      setCollapsed($section, !$section.hasClass('is-collapsed'));
    });
  }

  function initEpicPanel() {
    var $root = $('#sanan-backlog');
    var $panel = $('#backlog-epic-panel');
    var $toggle = $('#backlog-epic-panel-toggle');
    if (!$panel.length || !$toggle.length) return;

    var storageKey = 'sanan-backlog-epic-panel-' + ($root.attr('data-project-id') || '0');

    function setVisible(visible) {
      $root.toggleClass('epic-panel-hidden', !visible);
      $panel.prop('hidden', !visible);
      $toggle.toggleClass('is-active', visible);
      $toggle.attr('aria-pressed', visible ? 'true' : 'false');
      try {
        localStorage.setItem(storageKey, visible ? '1' : '0');
      } catch (err) { /* ignore */ }
    }

    var stored = null;
    try {
      stored = localStorage.getItem(storageKey);
    } catch (err) {
      stored = null;
    }
    setVisible(stored !== '0');

    $toggle.on('click', function (e) {
      e.preventDefault();
      setVisible($panel.prop('hidden') || $root.hasClass('epic-panel-hidden'));
    });

    $('#backlog-epic-panel-hide').on('click', function (e) {
      e.preventDefault();
      setVisible(false);
    });

    var $createForm = $('#backlog-epic-create-form');
    var $createToggle = $('#backlog-epic-create-toggle');
    var $createCancel = $('#backlog-epic-create-cancel');

    function showCreate(show) {
      if (!$createForm.length) return;
      $createForm.prop('hidden', !show);
      $createToggle.toggle(!show);
      if (show) {
        $createForm.find('input[name="subject"]').trigger('focus');
      }
    }

    $createToggle.on('click', function (e) {
      e.preventDefault();
      showCreate(true);
    });
    $createCancel.on('click', function (e) {
      e.preventDefault();
      showCreate(false);
    });
  }

  function initCompleteSprintModal() {
    var $modal = $('#backlog-complete-modal');
    if (!$modal.length) return;

    var $form = $('#backlog-complete-form');
    var $select = $('#backlog-complete-move-to');
    var $moveWrap = $('#backlog-complete-move-wrap');
    var $title = $('#backlog-complete-title');
    var $summary = $('#backlog-complete-summary');

    function closeModal() {
      $modal.prop('hidden', true);
      $('body').removeClass('backlog-complete-modal-open');
    }

    function openModal($btn) {
      var name = $btn.attr('data-name') || '';
      var completed = parseInt($btn.attr('data-completed'), 10) || 0;
      var openCount = parseInt($btn.attr('data-open'), 10) || 0;
      var url = $btn.attr('data-url');
      var moveOptions = [];
      try {
        moveOptions = JSON.parse($btn.attr('data-move-options') || '[]');
      } catch (err) {
        moveOptions = [];
      }

      var titleTpl = $modal.attr('data-title-template') || 'Complete __NAME__';
      $title.text(titleTpl.replace('__NAME__', name));

      var summaryTpl = $modal.attr('data-summary-template') ||
        'This sprint contains __COMPLETED__ completed work items and __OPEN__ open work items.';
      $summary.html(
        summaryTpl
          .replace('__COMPLETED__', '<strong>' + completed + '</strong>')
          .replace('__OPEN__', '<strong>' + openCount + '</strong>')
      );

      $('#backlog-complete-completed-hint').text($modal.attr('data-completed-hint') || '');
      $('#backlog-complete-open-hint').text($modal.attr('data-open-hint') || '');

      $select.empty();
      moveOptions.forEach(function (opt) {
        $select.append($('<option/>').attr('value', opt.value).text(opt.label));
      });
      if (openCount > 0) {
        $moveWrap.show();
        // Prefer backlog when available
        if ($select.find('option[value="backlog"]').length) {
          $select.val('backlog');
        }
      } else {
        $moveWrap.hide();
        $select.val('');
      }

      $form.attr('action', url);
      $modal.prop('hidden', false);
      $('body').addClass('backlog-complete-modal-open');
    }

    $(document).on('click', '.backlog-complete-trigger', function (e) {
      e.preventDefault();
      openModal($(this));
    });

    $modal.on('click', '[data-complete-dismiss]', function (e) {
      e.preventDefault();
      closeModal();
    });

    $(document).on('keydown', function (e) {
      if (e.key === 'Escape' && !$modal.prop('hidden')) {
        closeModal();
      }
    });
  }
})(window.jQuery);
