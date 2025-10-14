(function () {
  function contrast(hex) {
    if (!hex) return '#1A1E23';
    var h = ('' + hex).trim();
    if (h[0] !== '#') h = '#' + h;
    if (!/^#[0-9A-Fa-f]{6}$/.test(h)) return '#1A1E23';
    var r = parseInt(h.substr(1, 2), 16),
      g = parseInt(h.substr(3, 2), 16),
      b = parseInt(h.substr(5, 2), 16);
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) > 140 ? '#1A1E23' : '#fff';
  }

  function applyColor(card, bg, mode) {
    // reset trước (phòng đổi mode)
    card.style.backgroundColor = '';
    // card.style.color = '';
    card.style.borderLeft = '';

    var links = card.querySelectorAll('a');
    links.forEach(function (a) { a.style.color = ''; });

    if (mode === 'border') {
      // chỉ viền trái
      card.style.borderLeft = '5px solid ' + bg;
      return;
    }

    // mode 'body' (default): tô nền + đổi màu chữ + viền theo màu chữ
    var fg = contrast(bg);
    card.style.backgroundColor = bg;
    // card.style.color = fg;
    card.style.borderLeft = '0px solid #d1d3e0';
    links.forEach(function (a) {
      var parentP = a.closest('p');

      // nếu thẻ cha tồn tại và có class 'attributes' → bỏ qua (không đổi màu)
      if (parentP && parentP.classList.contains('attributes')) {
        return; // skip
      }
    
      // ngược lại: đổi màu (hoặc xử lý khác)
      a.style.color = fg;
    });
  }

  function extractTrackerName(card) {
    var idEl = card.querySelector('.issue-id');
    if (!idEl) return null;
    var txt = (idEl.textContent || '').trim();
    var hash = txt.indexOf('#');
    if (hash <= 0) return null;
    return txt.substring(0, hash).trim();
  }

  function paintAll(root) {
    var map = window.SANAN_TRACKER_COLORS || {};
    var mode = (window.SANAN_TRACKER_COLOR_MODE || 'body').toLowerCase();
    if (!map || Object.keys(map).length === 0) return;

    var cards = (root || document).querySelectorAll('.issue-card');
    cards.forEach(function (card) {
      var name = extractTrackerName(card);
      if (!name) return;
      var color = map[name];
      if (!color) return;
      applyColor(card, color, mode);
    });
  }

  function boot(root) { paintAll(root || document); }

  // if (document.readyState === 'loading') {
  //   document.addEventListener('DOMContentLoaded', function(){ boot(document); });
  // } else {
  //   boot(document);
  // }

  var mo = new MutationObserver(function (muts) {
    var need = false;
    muts.forEach(function (m) {
      if (!m.addedNodes) return;
      m.addedNodes.forEach(function (n) {
        if (n && n.nodeType === 1) {
          if ((n.matches && (n.matches('.issue-card')))) {
            need = true;
          }
        }
      });
    });
    if (need) boot(document);
  });
  mo.observe(document.documentElement, { childList: true, subtree: true });
})();
