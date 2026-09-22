(function ($) {
  'use strict';

  function mountAgileSprintActions() {
    var host = document.getElementById('sa-agile-sprint-actions');
    var bar = document.querySelector('#content > .contextual') || document.querySelector('.contextual');
    if (!host || !bar) return;
    var nodes = Array.prototype.slice.call(host.children);
    for (var i = nodes.length - 1; i >= 0; i--) {
      bar.insertBefore(nodes[i], bar.firstChild);
    }
    host.remove();
  }

  function initCompleteSprintModal() {
    var $modal = $('#backlog-complete-modal');
    if (!$modal.length) return;

    var $form = $('#backlog-complete-form');
    var $select = $('#backlog-complete-move-to');
    var $moveWrap = $('#backlog-complete-move-wrap');
    var $title = $('#backlog-complete-title');
    var $summary = $('#backlog-complete-summary');
    var $dodWrap = $('#backlog-complete-dod-wrap');
    var $dodList = $('#backlog-complete-dod-list');
    var $dodConfirmed = $('#backlog-complete-dod-confirmed');
    var dodCandidates = [];

    function parseDataJson($el, name) {
      var raw = $el.attr('data-' + name);
      if (raw) {
        try { return JSON.parse(raw); } catch (err) {}
      }
      var camel = name.replace(/-([a-z])/g, function (_, c) { return c.toUpperCase(); });
      var val = $el.data(name) || $el.data(camel);
      return Array.isArray(val) ? val : [];
    }

    function closeModal() {
      $modal.prop('hidden', true);
      $('body').removeClass('backlog-complete-modal-open');
    }

    function fmtSp(n) {
      n = Number(n) || 0;
      return (Math.round(n) === n) ? String(n) : String(Math.round(n * 100) / 100);
    }

    function escapeHtml(s) {
      return String(s == null ? '' : s)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
    }

    function flagsHtml(issue) {
      var bits = [];
      if (issue.closed) bits.push('<span class="backlog-complete-flag">Closed</span>');
      if (issue.be) bits.push('<span class="backlog-complete-flag">BE</span>');
      if (issue.fe) bits.push('<span class="backlog-complete-flag">FE</span>');
      if (issue.qa) bits.push('<span class="backlog-complete-flag">QA</span>');
      return bits.join('');
    }

    function syncDodToggleLabel() {
      var $btn = $('#backlog-complete-dod-all');
      var $boxes = $dodList.find('.backlog-complete-dod-check');
      var allOn = $boxes.length > 0 && $boxes.filter(':checked').length === $boxes.length;
      $btn.text(allOn ? ($btn.attr('data-label-none') || 'Unselect all')
                      : ($btn.attr('data-label-all') || 'Select all'));
    }

    function syncDodActual() {
      var total = 0;
      var be = 0;
      var fe = 0;
      var qa = 0;
      dodCandidates.forEach(function (issue) {
        if (issue.be) be += Number(issue.sp_be) || 0;
        if (issue.fe) fe += Number(issue.sp_fe) || 0;
        if (issue.qa) qa += Number(issue.sp_qa) || 0;
      });
      $dodList.find('.backlog-complete-dod-check:checked').each(function () {
        total += Number($(this).attr('data-sp')) || 0;
      });
      $('#backlog-complete-actual-sp').text(fmtSp(total));
      $('#backlog-complete-actual-be').text(fmtSp(be));
      $('#backlog-complete-actual-fe').text(fmtSp(fe));
      $('#backlog-complete-actual-qa').text(fmtSp(qa));
      syncDodToggleLabel();
    }

    function renderDod(candidates) {
      dodCandidates = Array.isArray(candidates) ? candidates : [];
      $dodList.empty();
      if (!dodCandidates.length) {
        $dodWrap.prop('hidden', true);
        $dodConfirmed.prop('disabled', true);
        return;
      }
      $dodWrap.prop('hidden', false);
      $dodConfirmed.prop('disabled', false);
      dodCandidates.forEach(function (issue) {
        var checked = issue.dod ? ' checked' : '';
        var $li = $(
          '<li class="backlog-complete-modal__dod-item">' +
            '<label>' +
              '<input type="checkbox" class="backlog-complete-dod-check" name="dod_issue_ids[]" value="' +
                escapeHtml(issue.id) + '" data-sp="' + escapeHtml(issue.sp) + '"' + checked + '>' +
              '<span class="backlog-complete-dod-id">#' + escapeHtml(issue.id) + '</span>' +
              '<span class="backlog-complete-dod-meta">' +
                escapeHtml(issue.tracker) + ' · ' + escapeHtml(issue.subject) +
              '</span>' +
              '<span class="backlog-complete-dod-flags">' + flagsHtml(issue) + '</span>' +
              '<span class="backlog-complete-dod-sp">' + fmtSp(issue.sp) + ' SP</span>' +
            '</label>' +
          '</li>'
        );
        $dodList.append($li);
      });
      syncDodActual();
    }

    function openModal($btn) {
      var name = $btn.attr('data-name') || '';
      var completed = parseInt($btn.attr('data-completed'), 10) || 0;
      var openCount = parseInt($btn.attr('data-open'), 10) || 0;
      var url = $btn.attr('data-url');
      var moveOptions = parseDataJson($btn, 'move-options');
      var dod = parseDataJson($btn, 'dod-candidates');

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
        if ($select.find('option[value="backlog"]').length) {
          $select.val('backlog');
        }
      } else {
        $moveWrap.hide();
        $select.val('');
      }

      renderDod(dod);
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

    $dodList.on('change', '.backlog-complete-dod-check', syncDodActual);

    $('#backlog-complete-dod-all').on('click', function (e) {
      e.preventDefault();
      var $boxes = $dodList.find('.backlog-complete-dod-check');
      var allOn = $boxes.length && $boxes.filter(':checked').length === $boxes.length;
      $boxes.prop('checked', !allOn);
      syncDodActual();
    });

    $(document).on('keydown', function (e) {
      if (e.key === 'Escape' && !$modal.prop('hidden')) {
        closeModal();
      }
    });
  }

  $(document).ready(function () {
    mountAgileSprintActions();
    initCompleteSprintModal();
  });
})(jQuery);
