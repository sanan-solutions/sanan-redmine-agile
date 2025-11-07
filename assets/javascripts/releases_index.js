(function(){
document.addEventListener("DOMContentLoaded", ()=>{
    // Search + Filter -> reload with query params (reset page)
    const q = document.getElementById('rel-search');
    const f = document.getElementById('rel-filter');
    function navigateWithParams(){
      const params = new URLSearchParams(window.location.search);
      const qv = (q?.value || '').trim();
      if (qv) params.set('q', qv); else params.delete('q');
      const fv = f?.value || '';
      if (fv) params.set('state', fv); else params.delete('state');
      params.delete('page'); // reset về trang 1 khi đổi điều kiện
      const qs = params.toString();
      window.location.search = qs;
    }
    if (q) q.addEventListener('keydown', e => { if (e.key === 'Enter') navigateWithParams(); });
    if (f) f.addEventListener('change', navigateWithParams);
  
  
    const token = document.querySelector('meta[name="csrf-token"]')?.content;
    const modal = document.getElementById('rel-modal');
    const body  = document.getElementById('rel-modal-body');
    const btn   = document.getElementById('rel-create');
  
    if (!btn) return;
  
    btn.addEventListener('click', async () => {
      const url = location.pathname.replace(/\/releases.*/, '') + '/releases/new';
      const html = await fetch(url, { headers: {'X-Requested-With':'XMLHttpRequest'} }).then(r=>r.text());
      body.innerHTML = html;
      modal.hidden = false;
  
      const form = body.querySelector('#rel-create-form');
      form.addEventListener('submit', async (e)=>{
        e.preventDefault();
        const fd = new FormData(form);
        const res = await fetch(form.action, { method:'POST', headers:{'X-CSRF-Token': token}, body: fd }).then(r=>r.json());
        if (res.ok) location.href = res.url;
        else alert(res.errors?.join('\n') || 'Create failed');
      });
    });
  
    modal.addEventListener('click', (e)=>{
      if (e.target.classList.contains('modal__close') || e.target === modal) modal.hidden = true;
    });
})
})();
