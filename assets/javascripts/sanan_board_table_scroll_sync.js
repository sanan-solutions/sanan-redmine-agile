(function () {
  // Tìm bảng header/body theo DOM bạn cung cấp
  function grabTables(root) {
    const header = root.querySelector('table.list.issues-board.sticky');
    const body = root.querySelector('table.list.issues-board:not(.sticky)');
    return { header, body };
  }

  // Tìm scroll container theo trục X (tổ tiên có scrollWidth > clientWidth)
  function findScrollParentX(el) {
    // let n = el && el.parentElement;
    // while (n) {
    //   const style = getComputedStyle(n);
    //   const hasXScroll =
    //     (n.scrollWidth > n.clientWidth) &&
    //     (/(auto|scroll)/i.test(style.overflowX) || /(auto|scroll)/i.test(style.overflow));
    //   if (hasXScroll) return n;
    //   n = n.parentElement;
    // }
    // // fallback: documentElement nếu không có container cuộn riêng
    // return document.scrollingElement || document.documentElement;

    return document.querySelector('div.agile-board-scroll-wrapper')
  }

  function ensureSync(root) {
    const { header, body } = grabTables(root);
    console.log("header body", header, body)
    if (!header || !body) return;

    const scroller = findScrollParentX(body);
    console.log("scho", scroller)

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

    // Lần đầu
    applyWidths();
    const timeout = setTimeout(()=>{
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

  // Board có thể re-render → gắn lại
  // const mo = new MutationObserver((muts) => {
  //   for (const m of muts) {
  //     m.addedNodes && m.addedNodes.forEach(node => {
  //       console.log('node ne')
  //       if (!(node instanceof Element)) return;
  //       if (node.matches && (node.matches('table.list.issues-board') || node.matches('.container-fixed') || node.matches('.agile-board'))) {
  //         console.log("run ne 1")
  //         boot(node);
  //       } 
  //       // else if (node.querySelector) {
  //       //   console.log("run ne 2")
  //       //   const hit = node.querySelector('table.list.issues-board');
  //       //   if (hit) boot(node);
  //       // }
  //     });
  //   }
  // });
  // mo.observe(document.documentElement, { childList: true, subtree: true });
})();
