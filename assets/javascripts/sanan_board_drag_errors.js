/**
 * Harden Agile board drag error UX without patching redmine_agile sources.
 * Waits for redmine_agile globals, then overrides parseErrorResponse / setErrorMessage.
 */
(function () {
  var FALLBACK = 'That move is not possible';
  var tries = 0;

  function parseBoardError(responseText) {
    if (responseText == null || responseText === '') return '';

    try {
      var errors = JSON.parse(responseText);
      if (typeof errors === 'string') return errors;
      if (errors && typeof errors.error === 'string') return errors.error;
      if (errors && errors.errors) errors = errors.errors;
      if (Array.isArray(errors) && errors.length > 0) {
        return errors.join('\n');
      }
    } catch (e) {
      /* not JSON */
    }

    var text = String(responseText)
      .replace(/<script[\s\S]*?<\/script>/gi, ' ')
      .replace(/<style[\s\S]*?<\/style>/gi, ' ')
      .replace(/<[^>]+>/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
    if (!text) return '';
    if (text.length > 180) text = text.slice(0, 180) + '…';
    return text;
  }

  function showBoardError(message, flashClass) {
    flashClass = flashClass || 'error';
    var text = message || FALLBACK;
    var $box = window.jQuery ? jQuery('div#agile-board-errors') : null;
    if (!$box || !$box.length) {
      window.alert(text);
      return;
    }
    $box.removeClass().addClass('flash ' + flashClass);
    $box.html(jQuery('<div/>').text(text).html().replace(/\n/g, '<br>')).show();
    setTimeout(function () {
      $box.removeClass();
      $box.html('').hide();
    }, 8000);
  }

  function patchGlobals() {
    if (typeof window.parseErrorResponse !== 'function' ||
        typeof window.setErrorMessage !== 'function') {
      tries += 1;
      if (tries < 40) setTimeout(patchGlobals, 50);
      return;
    }

    window.parseErrorResponse = function (responseText) {
      return parseBoardError(responseText) || FALLBACK;
    };
    window.setErrorMessage = showBoardError;
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', patchGlobals);
  } else {
    patchGlobals();
  }
})();
