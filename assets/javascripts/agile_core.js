(function (w, d) {
  if (w.SananAgileUtil) return; // guard chống redefine

  function $(sel, root) { return (root || document).querySelector(sel); }
  function $all(s, r) { return Array.prototype.slice.call((r || d).querySelectorAll(s)); }

  function debounce(fn, ms) { var t; return function () { if (t) clearTimeout(t); t = setTimeout(fn, ms); }; }

  function toggleChecked(el, val) {
    el.checked = !!val;
    if (el.checked) {
      el.setAttribute('checked', 'checked');
      return;
    }

    el.removeAttribute('checked');
  }

  // Tìm issue_id (support cả div card & tr.issue)
  function findIssueId(node) {
    if (node.matches && node.matches('tr.issue')) {
      var id = node.getAttribute('data-id'); if (id) return id;
      var m = (node.id || '').match(/issue[-_](\d+)/i); if (m) return m[1];
    }
    return node.getAttribute('data-issue-id')
      || node.getAttribute('data-id')
      || (function () {
        var a = node.querySelector('a[href*="/issues/"]');
        if (!a) return null;
        var m = a.getAttribute('href').match(/\/issues\/(\d+)/);
        return m ? m[1] : null;
      })()
      || null;
  }

  // Container để gắn header/footer
  function pickHeaderContainer(node) {
    return node; // header đặt trên cùng của card (div case)
  }
  function pickFooterContainer(node) {
    if (node.matches && node.matches('tr.issue')) {
      return node.querySelector('td.name, td.subject') || node.querySelector('td') || node;
    }
    return node;
  }

  // Lấy status_id từ cột (nếu board dạng table)
  function statusIdFromDOM(card) {
    var td = card.closest('td');
    if (td) {
      var idx = td.cellIndex;
      var th = td.closest('table').querySelector('thead th:nth-child(' + (idx + 1) + ')');
      if (th && th.getAttribute('data-column-id')) {
        return parseInt(th.getAttribute('data-column-id'), 10);
      }
    }
    return null;
  }

  // Mount helper: đăng ký 1 “component” reconcile(card) để quét toàn board + auto remount
  var components = [];
  let observer = null;

  function register(component) { components.push(component); }

  function scan() {
    var nodes = []
      .concat($all('.agile__issue, .agile-card, .issue-card, .card'))
    // .concat($all('table.list.issues-board tr.issue'));

    for (var i = 0; i < components.length; i++) {
      var rec = components[i];
      nodes.forEach(function (n) { try { rec(n); } catch (e) { /* no-op */ } });
    }

    try {
      sortAgileBoardColumnsByPriority();
    } catch (e) {}
  }

  function sortAgileBoardColumnsByPriority() {
    var pMap = {
      'priority-highest': 5,
      'priority-high2': 4,
      'priority-high3': 3,
      'priority-default': 2,
      'priority-lowest': 1
    };

    var columns = d.querySelectorAll('table.issues-board tbody tr td');
    if (!columns || columns.length === 0) return;

    columns.forEach(function(col) {
      // Find all issue cards directly inside this column (or inside a list container if applicable)
      // Usually redmine_agile places them right inside `td` or a `ul`/`div` container.
      // We will select the immediate parent of issue cards and sort its children.
      var firstCard = col.querySelector('.issue-card');
      if (!firstCard) return;

      var container = firstCard.parentNode;
      var cards = Array.prototype.slice.call(container.querySelectorAll('.issue-card'));
      if (cards.length < 2) return;

      var currentOrder = cards.map(function(c) { return c.getAttribute('data-id'); }).join(',');

      // Map format with index for stable sorting
      var mapped = cards.map(function(el, i) {
        var w = 0;
        var pNode = el.querySelector('.priority');
        if (pNode) {
          var cls = pNode.className.split(' ');
          for(var j = 0; j < cls.length; j++) {
            if(pMap[cls[j]] !== undefined) {
              w = pMap[cls[j]];
              break;
            }
          }
        }
        return { el: el, index: i, weight: w };
      });

      mapped.sort(function(a, b) {
        if (a.weight !== b.weight) {
          return b.weight - a.weight; // Descending
        }
        return a.index - b.index; // Stable sort
      });

      var newOrder = mapped.map(function(item) { return item.el.getAttribute('data-id'); }).join(',');

      if (currentOrder !== newOrder) {
        mapped.forEach(function(item) {
          container.appendChild(item.el);
        });
      }
    });
  }

  var scanDebounced = debounce(scan, 400);

  function boot(usingObserver) {
    if (d.readyState === 'loading') {
      d.addEventListener('DOMContentLoaded', scan);
    } else {
      scan();
    }

    try {
      if (observer || !usingObserver) {
        return
      }

      var target = d.querySelector('#content') || d.documentElement;
      if (!target) return;

      observer = new MutationObserver(function (muts) {
        for (var i = 0; i < muts.length; i++) {
          var m = muts[i];
          if ((m.addedNodes && m.addedNodes.length) || (m.removedNodes && m.removedNodes.length)) {
            scanDebounced();
            return;
          }
        }
      });

      observer.observe(target, { childList: true, subtree: true });
    } catch (_) { }
  }

  /////////
  function isBR(n) { return n && n.nodeType === 1 && n.tagName === 'BR'; }
  function isWsText(n) { return n && n.nodeType === 3 && !/\S/.test(n.nodeValue || ''); }

  function tidyAttributesBlock(p) {
    if (!p) return;
    // 1) bỏ text trắng
    var cur = p.firstChild, next;
    while (cur) {
      next = cur.nextSibling;
      if (isWsText(cur)) p.removeChild(cur);
      cur = next;
    }
    // 2) gộp các <br> liên tiếp
    var lastWasBR = false;
    cur = p.firstChild;
    while (cur) {
      next = cur.nextSibling;
      if (isBR(cur)) {
        if (lastWasBR) { p.removeChild(cur); }
        lastWasBR = true;
      } else {
        lastWasBR = false;
      }
      cur = next;
    }
    // 3) bỏ <br> đầu/cuối
    while (isBR(p.firstChild)) p.removeChild(p.firstChild);
    while (isBR(p.lastChild)) p.removeChild(p.lastChild);
  }

  function findAttributesBlock(card) {
    return card.querySelector('p.attributes');
  }

  function norm(s) { return String(s || '').trim().replace(/\s+/g, ' ').toLowerCase(); }
  function findAttributeLabel(card, attributeName) {
    var p = findAttributesBlock(card);
    if (!p) return null;
    var bs = p.querySelectorAll('b');
    for (var i = 0; i < bs.length; i++) {
      if (norm(bs[i].textContent) === norm(attributeName)) return bs[i];
    }
    return null;
  }

  // XÓA CẢ DÒNG (label + value) & dọn <br> thừa
  function removeAttributeLine(card, attributeName) {
    var p = findAttributesBlock(card);
    if (!p) return;
    var label = findAttributeLabel(card, attributeName);
    if (!label) return;

    // xoá label + các node theo sau cho tới <b> kế tiếp
    var n = label, next;
    while (n) {
      next = n.nextSibling;
      var stop = (n !== label && n.nodeType === 1 && n.tagName === 'B');
      if (stop) break;
      p.removeChild(n);
      n = next;
    }
    // xoá <br> ngay trước label (nếu có)
    var prev = label.previousSibling;
    while (isWsText(prev)) {
      var _t = prev.previousSibling;
      p.removeChild(prev);
      prev = _t;
    }

    if (isBR(prev)) {
      p.removeChild(prev);
    }

    tidyAttributesBlock(p);
  }

  // THÊM LẠI DÒNG (label + “: ” + <a>) – không sinh thêm dòng trống
  function addAttributeLine(card, value, href, attributeName) {
    var p = findAttributesBlock(card);
    if (!p) return;

    // clear dòng cũ (nếu có)
    removeAttributeLine(card, attributeName);

    // chỉ thêm <br> nếu block có nội dung và phần tử cuối KHÔNG là <br>
    if (p.lastChild && !isBR(p.lastChild)) p.appendChild(document.createElement('br'));

    var b = document.createElement('b');
    b.textContent = attributeName;
    p.appendChild(b);
    p.appendChild(document.createTextNode(': '));

    var a = document.createElement('a');
    a.textContent = String(value || '');
    if (href) a.href = href;
    a.target = '_blank';
    p.appendChild(a);

    tidyAttributesBlock(p);
  }

  w.SananAgileUtil = {
    $: $,
    $all: $all,
    debounce: debounce,
    toggleChecked: toggleChecked,
    findIssueId: findIssueId,
    pickHeaderContainer: pickHeaderContainer,
    pickFooterContainer: pickFooterContainer,
    statusIdFromDOM: statusIdFromDOM,
    register: register,
    boot: boot,
    removeAttributeLine,
    addAttributeLine,
  };
})(window, document);