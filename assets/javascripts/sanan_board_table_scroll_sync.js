(function () {
  // Tìm bảng header/body
  function grabTables(root) {
    const header = root.querySelector('table.list.issues-board.sticky');
    const body = root.querySelector('table.list.issues-board:not(.sticky)');
    return { header, body };
  }

  // Tìm scroll container theo trục X (tổ tiên có scrollWidth > clientWidth)
  function findScrollParentX(el) {
    return document.querySelector('div.agile-board-scroll-wrapper')
  }

  function ensureSync(root) {
    const { header, body } = grabTables(root);
    if (!header || !body) return;

    const scroller = findScrollParentX(body);

    // Căn độ rộng header theo nội dung body
    const applyWidths = () => {
      const w = Math.max(body.scrollWidth, body.clientWidth);
      header.style.width = w + 'px';          // bề rộng toàn bảng header
      // Dịch trái theo scrollLeft để “đi theo” phần đang nhìn của body
      header.style.marginLeft = (-scroller.scrollLeft) + 'px';
    };

    // Đồng bộ khi kéo ngang
    const onScroll = () => {
      header.style.marginLeft = (-scroller.scrollLeft) + 'px';
    };

    // Gỡ listener cũ nếu có
    scroller.__sanan_unbind && scroller.__sanan_unbind();

    scroller.addEventListener('scroll', onScroll, { passive: true });
    window.addEventListener('resize', applyWidths);

    scroller.__sanan_unbind = () => {
      scroller.removeEventListener('scroll', onScroll);
      window.removeEventListener('resize', applyWidths);
      scroller.__sanan_unbind = null;
    };

    applyWidths();
    const timeout = setTimeout(() => {
      applyWidths()
      clearTimeout(timeout)
    }, 50);
  }

  function boot(target) {
    ensureSync(target || document);
  }

  // Khởi tạo
  document.addEventListener('DOMContentLoaded', () => {
    const timeout = setTimeout(() => {
      boot(document)
      clearTimeout(timeout)
    })
  });
})();
