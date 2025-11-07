// ---------- Loading Overlay ----------
function saShowLoading(text = 'Updating release…') {
  if (document.getElementById('sa-overlay')) return;
  const wrap = document.createElement('div');
  wrap.className = 'sa-overlay';
  wrap.id = 'sa-overlay';
  wrap.innerHTML = `
    <div class="sa-overlay__card" role="alert" aria-live="assertive">
      <div class="sa-spinner" aria-hidden="true"></div>
      <div class="sa-overlay__text">${text}</div>
    </div>`;
  document.body.appendChild(wrap);
  document.body.classList.add('sa-body-busy');
}
function saHideLoading() {
  const el = document.getElementById('sa-overlay');
  if (el) el.remove();
  document.body.classList.remove('sa-body-busy');
}

// ---------- Pretty Alert (error) ----------
function saAlertError(title = 'Update failed', message = '', details = null) {
  // remove existing
  const prev = document.getElementById('sa-alert');
  if (prev) prev.remove();

  const host = document.createElement('div');
  host.className = 'sa-alert';
  host.id = 'sa-alert';
  host.innerHTML = `
    <div class="sa-alert__panel" role="dialog" aria-modal="true" aria-labelledby="sa-alert-title">
      <div class="sa-alert__header">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="#991b1b" aria-hidden="true"><path d="M12 9v4m0 4h.01M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/></svg>
        <h3 id="sa-alert-title" class="sa-alert__title">${title}</h3>
      </div>
      <div class="sa-alert__body">
        <div>${message || 'Something went wrong.'}</div>
        ${details ? `<pre>${escapeHtml(typeof details === 'string' ? details : JSON.stringify(details, null, 2))}</pre>` : ''}
      </div>
      <div class="sa-alert__footer">
        <button class="sa-btn" id="sa-alert-copy" ${details ? '' : 'style="display:none"'}>Copy details</button>
        <button class="sa-btn sa-btn--primary" id="sa-alert-close">Close</button>
      </div>
    </div>
  `;
  document.body.appendChild(host);

  // focus trap-ish
  const closeBtn = document.getElementById('sa-alert-close');
  closeBtn?.focus();

  host.addEventListener('click', (e) => { if (e.target === host) host.remove(); });
  closeBtn?.addEventListener('click', () => host.remove());
  document.getElementById('sa-alert-copy')?.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(typeof details === 'string' ? details : JSON.stringify(details, null, 2));
      closeBtn.textContent = 'Copied ✓'; setTimeout(() => closeBtn.textContent = 'Close', 1000);
    } catch (_) { }
  });

  function escapeHtml(s) { return s.replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])); }
}

(function () {
  if (window.__saTooltipInitialized) return;
  window.__saTooltipInitialized = true; // đánh dấu đã khởi tạo

  let tip = document.querySelector('.sa-tooltip');
  if (!tip) {
    tip = document.createElement('div');
    tip.className = 'sa-tooltip';
    document.body.appendChild(tip);
  }
  let activeEl = null;

  function show(text, x, y) {
    tip.textContent = text || '';
    // đặt vị trí sơ bộ
    tip.style.left = x + 'px';
    tip.style.top = y + 'px';
    tip.classList.add('is-visible');

    // tránh tràn viền viewport
    const rect = tip.getBoundingClientRect();
    let nx = x, ny = y;
    const pad = 8;
    if (rect.left < pad) nx = rect.width / 2 + pad;
    if (rect.right > window.innerWidth - pad) nx = window.innerWidth - rect.width / 2 - pad;
    if (rect.top < pad) ny = y + rect.height + 20; // nếu thiếu chỗ phía trên, đặt tooltip xuống dưới
    tip.style.left = nx + 'px';
    tip.style.top = ny + 'px';
  }

  function hide() {
    tip.classList.remove('is-visible');
  }

  // Delegation: lắng nghe hover trên mọi phần tử có data-tooltip
  document.addEventListener('mouseover', (e) => {
    const el = e.target.closest('[data-tooltip]');
    if (el && el !== activeEl) {
      activeEl = el;
    }
  });

  document.addEventListener('mousemove', (e) => {
    if (!activeEl) return;
    const text = activeEl.getAttribute('data-tooltip');
    if (!text) return hide();
    show(text, e.clientX, e.clientY);
  });

  document.addEventListener('mouseout', (e) => {
    if (activeEl && !e.relatedTarget?.closest('[data-tooltip]')) {
      activeEl = null;
      hide();
    }
  });

  // Ẩn khi scroll modal/body
  document.addEventListener('scroll', hide, true);
})();

// helper.js

(function (w, d) {
  w.SA = w.SA || {};

  // --- private: tạo 1 element nếu chưa có
  function ensureEl(id, html) {
    let el = d.getElementById(id);
    if (!el) {
      el = d.createElement('div');
      el.id = id;
      el.innerHTML = html || '';
      d.body.appendChild(el);
    }
    return el;
  }

  // --- PUBLIC: UI blocker (loading overlay)
  SA.blockUI = function (on) {
    const blocker = ensureEl('sa-page-blocker',
      '<div class="sa-blocker" hidden><div class="sa-spinner"></div></div>'
    ).firstElementChild;
    blocker.hidden = !on;
  };

  /**
   * PUBLIC: showConfirm(opts)
   * Hiển thị dialog xác nhận. Trả về API để gắn handler và điều khiển dialog.
   *
   * @param {Object} opts
   *  - title, desc (HTML), note (optional, HTML), confirmText, cancelText
   *  - danger (bool) -> (tuỳ bạn thêm style)
   *  - closeOnOutside (default true)
   *
   * @returns {Object} api
   *  - onConfirm(cb), onCancel(cb), close(), setError(msg), setNote(html)
   */
  SA.showConfirm = function showConfirm(opts = {}) {
    const {
      title = 'Confirm',
      desc = 'Are you sure?',
      note = '',
      confirmText = 'Confirm',
      cancelText = 'Cancel',
      closeOnOutside = true
    } = opts;

    // Tạo khung modal (singleton)
    const host = ensureEl(
      'sa-confirm-host',
      `<div id="sa-confirm-modal" class="modal" hidden>
         <div class="modal__panel sa-dialog">
           <div class="modal__header">
             <h3 id="sa-cf-title"></h3>
             <button class="modal__close" type="button" aria-label="Close">×</button>
           </div>
           <div class="modal__body">
             <div class="sa-dialog__icon">⚠️</div>
             <div class="sa-dialog__text">
               <p class="sa-dialog__title" id="sa-cf-desc"></p>
               <div id="sa-cf-note" class="sa-dialog__note" hidden></div>
               <div id="sa-cf-error" class="sa-dialog__error" hidden></div>
             </div>
           </div>
           <div class="actions actions--split">
             <button type="button" class="btn-ghost" id="sa-cf-cancel">${cancelText}</button>
             <button type="button" class="button-primary" id="sa-cf-ok">${confirmText}</button>
           </div>
         </div>
       </div>`
    );

    const modal = d.getElementById('sa-confirm-modal');
    const elT = d.getElementById('sa-cf-title');
    const elD = d.getElementById('sa-cf-desc');
    const elN = d.getElementById('sa-cf-note');
    const elE = d.getElementById('sa-cf-error');
    const btnX = modal.querySelector('.modal__close');
    const btnOk = d.getElementById('sa-cf-ok');
    const btnNo = d.getElementById('sa-cf-cancel');

    elT.textContent = title;
    elD.innerHTML = desc;
    if (note) { elN.hidden = false; elN.innerHTML = note; } else { elN.hidden = true; elN.innerHTML = ''; }
    elE.hidden = true; elE.textContent = '';

    modal.hidden = false;

    const close = () => { modal.hidden = true; elE.hidden = true; };

    let onOk = null, onCancel = null;

    function cleanup() {
      btnOk.onclick = btnNo.onclick = btnX.onclick = null;
      if (closeOnOutside) modal.onclick = null;
    }

    btnOk.onclick = () => { if (onOk) onOk(); cleanup(); };
    btnNo.onclick = () => { if (onCancel) onCancel(); close(); cleanup(); };
    btnX.onclick = () => { if (onCancel) onCancel(); close(); cleanup(); };
    if (closeOnOutside) {
      modal.addEventListener('click', (e) => { if (e.target === modal) { if (onCancel) onCancel(); close(); cleanup(); } });
    }

    return {
      onConfirm(cb) { onOk = cb; return this; },
      onCancel(cb) { onCancel = cb; return this; },
      setError(msg) { elE.hidden = !msg; elE.textContent = msg || ''; return this; },
      setNote(html) { if (html) { elN.hidden = false; elN.innerHTML = html; } else { elN.hidden = true; elN.innerHTML = ''; } return this; },
      close
    };
  };

  /**
   * PUBLIC: confirm(opts) -> Promise<boolean>
   * tiện hơn nếu bạn chỉ cần true/false
   */
  SA.confirm = function (opts) {
    return new Promise((resolve) => {
      const api = SA.showConfirm(opts);
      api.onConfirm(() => { api.close(); resolve(true); })
        .onCancel(() => { api.close(); resolve(false); });
    });
  };

})(window, document);