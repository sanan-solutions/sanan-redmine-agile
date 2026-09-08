document.addEventListener("DOMContentLoaded", function () {
  bootSananGlobalModal();
});

if (document.readyState !== 'loading') {
  bootSananGlobalModal();
}

function bootSananGlobalModal() {
  if (window.__sananGlobalModalBooted) return;
  window.__sananGlobalModalBooted = true;

  // Handler cho Agile board
  const globalModalElementId = "global-modal"
  const modal = document.getElementById(globalModalElementId);
  if (!modal) return;
  const modalTitle = modal.querySelector(".header__title")
  const modalBody = modal.querySelector(".content__body");

  const closeButton = modal.querySelector('.header__close-btn');
  const scrollBtn = document.getElementById('modal-scroll-top');

  let currentStatusId = null; // TODO: luw parent current status
  let isHotReload = false;
  let backlogTicketNav = null; // { sectionLabel, tickets: [{id, subject, status}], currentId }
  const SubmitFormType = {
    CREATE: 'create',
    CREATE_AND_ADD_ANOTHER: 'Create and add another',
    CREATE_AND_FOLLOW: 'Create and follow',
    SUBMIT: 'submit',
  }
  let submitFormType = SubmitFormType.CREATE
  let isWasSubmitted = false;
  const Action = {
    VIEW: 'view',
    CREATE: 'create',
    CREATE_SUB_TASK: 'create_sub_task',
    UPDATE: 'update'
  }
  let action = Action.VIEW; // create, update, view

  function getProjectId() {
    return window.location.pathname.split('/')[2];
  }

  function initIssueTagsInModal() {
    const $root = $('#global-modal');
    const $sel = $root.find('#issue_tag_list, select.tags, .redmineup-tags');
    if (!$sel.length) return;

    // Nếu đã init nhầm trước đó -> phá rồi init lại cho sạch
    if ($sel.data('select2')) {
      try { $sel.select2('destroy'); } catch (e) { }
    }

    const url = $sel.attr('url');
    const placeholder = $sel.attr('placeholder') || '+ add tag';
    const tagsEnabled = String($sel.attr('tags')).toLowerCase() === 'true';

    if (window.select2Tag) {
      const originBuildSelect2Options = window.buildSelect2Options
      window.buildSelect2Options = function (options) {
        const result = originBuildSelect2Options(options)
        result['dropdownParent'] = $root;
        return result
      }

      window.select2Tag('issue_tag_list', {
        multiple: true,
        include_hidden: true,
        style: 'width:100%',
        url: url,
        placeholder: placeholder,
        tags: tagsEnabled,
      });
    }
  }

  function closeModal() {
    hideBacklogTicketNav();
    ScrollLock.unlock();
    modal.style.display = "none";
  }

  function escapeHtml(str) {
    return String(str == null ? '' : str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function collectBacklogTickets(fromRow) {
    const section = fromRow && fromRow.closest('.backlog-section');
    const rows = section
      ? section.querySelectorAll('tr.backlog-row')
      : document.querySelectorAll('.sanan-backlog tr.backlog-row');
    const sectionLabel = (section && section.querySelector('h3')
      ? section.querySelector('h3').textContent
      : 'Backlog').replace(/\s+/g, ' ').trim();

    const tickets = Array.from(rows).map(function (row) {
      const id = row.getAttribute('data-id');
      const subjectEl = row.querySelector('.backlog-issue-subject');
      const statusEl = row.querySelector('td.status');
      return {
        id: id,
        subject: subjectEl ? subjectEl.textContent.trim() : ('#' + id),
        status: statusEl ? statusEl.textContent.trim() : ''
      };
    }).filter(function (t) { return !!t.id; });

    return { sectionLabel: sectionLabel, tickets: tickets };
  }

  function selectText(form, selector) {
    const el = form.querySelector(selector);
    if (!el || !el.selectedOptions || !el.selectedOptions[0]) return '';
    return (el.selectedOptions[0].textContent || '').replace(/\s+/g, ' ').trim();
  }

  function isBlankAssigneeLabel(label) {
    if (!label) return true;
    return /^(—|-|none|<<?\s*none\s*>>?|«\s*none\s*»)$/i.test(label);
  }

  function extractIssuePatchFromForm(form) {
    if (!form) return {};
    const fd = new FormData(form);
    const subject = (fd.get('issue[subject]') || '').toString().trim();
    const status = selectText(form, '#issue_status_id');
    const tracker = selectText(form, '#issue_tracker_id');
    const priority = selectText(form, '#issue_priority_id');
    const assigned_to = selectText(form, '#issue_assigned_to_id');
    const patch = {};
    if (subject) patch.subject = subject;
    if (status) patch.status = status;
    if (tracker) patch.tracker = tracker;
    if (priority) patch.priority = priority;
    if (assigned_to) patch.assigned_to = assigned_to;
    return patch;
  }

  function attributeValueFromHtml(root, labelRegex) {
    const attrs = root.querySelectorAll('.attribute, .splitcontentleft .attribute, .splitcontentright .attribute');
    for (let i = 0; i < attrs.length; i++) {
      const label = (attrs[i].querySelector('.label')?.textContent || '').replace(/\s+/g, ' ').trim();
      if (!labelRegex.test(label)) continue;
      return (attrs[i].querySelector('.value')?.textContent || '').replace(/\s+/g, ' ').trim();
    }
    return '';
  }

  function parseIssueFieldsFromHtml(html) {
    const tmp = document.createElement('div');
    tmp.innerHTML = html || '';
    const subject =
      (tmp.querySelector('#content .subject h3')?.textContent ||
        tmp.querySelector('.subject h3')?.textContent ||
        tmp.querySelector('h3')?.textContent ||
        '').replace(/\s+/g, ' ').trim();
    const status = attributeValueFromHtml(tmp, /status/i);
    const tracker = attributeValueFromHtml(tmp, /tracker/i);
    const priority = attributeValueFromHtml(tmp, /priority/i);
    const assigned_to = attributeValueFromHtml(tmp, /assignee|assigned/i);
    const patch = {};
    if (subject) patch.subject = subject;
    if (status) patch.status = status;
    if (tracker) patch.tracker = tracker;
    if (priority) patch.priority = priority;
    if (assigned_to) patch.assigned_to = assigned_to;
    return patch;
  }

  let viewRequestSeq = 0;

  function getTicketNavShell() {
    // Always the shell aside (sibling of content body), never a nested copy from fetched HTML
    return modal.querySelector('.global-modal__body > #global-modal-ticket-nav');
  }

  function getTicketNavList() {
    const nav = getTicketNavShell();
    return nav ? nav.querySelector('#global-modal-ticket-nav-list') : null;
  }

  function getTicketNavSectionEl() {
    const nav = getTicketNavShell();
    return nav ? nav.querySelector('#global-modal-ticket-nav-section') : null;
  }

  function getTicketNavCountEl() {
    const nav = getTicketNavShell();
    return nav ? nav.querySelector('#global-modal-ticket-nav-count') : null;
  }

  function syncBacklogTicketNav(issueId, patch) {
    if (!backlogTicketNav || !issueId || !patch) return;

    backlogTicketNav.tickets = backlogTicketNav.tickets.map(function (t) {
      if (String(t.id) !== String(issueId)) return t;
      const next = Object.assign({}, t);
      if (patch.subject) next.subject = patch.subject;
      if (patch.status) next.status = patch.status;
      return next;
    });
    backlogTicketNav.currentId = String(issueId);

    // Update DOM in place — avoid full re-render wiping click highlight
    const list = getTicketNavList();
    if (list) {
      const safeId = String(issueId).replace(/\\/g, '\\\\').replace(/"/g, '\\"');
      const btn = list.querySelector('.ticket-nav__item[data-issue-id="' + safeId + '"]');
      if (btn) {
        if (patch.subject) {
          const subjectEl = btn.querySelector('.ticket-nav__subject');
          if (subjectEl) subjectEl.textContent = patch.subject;
        }
        if (patch.status) {
          let statusEl = btn.querySelector('.ticket-nav__status');
          const top = btn.querySelector('.ticket-nav__top');
          if (!statusEl && top) {
            statusEl = document.createElement('span');
            statusEl.className = 'ticket-nav__status';
            top.appendChild(statusEl);
          }
          if (statusEl) statusEl.textContent = patch.status;
        }
      }
    }

    setActiveTicketNav(issueId);
  }

  function syncBacklogTableRow(issueId, patch) {
    if (!issueId || !patch) return;
    const row = document.querySelector(
      '.sanan-backlog tr.backlog-row[data-id="' + issueId + '"], ' +
      '.sanan-backlog tr.backlog-row[data-issue-id="' + issueId + '"]'
    );
    if (!row) return;

    if (patch.subject) {
      row.querySelectorAll('.backlog-issue-subject').forEach(function (el) {
        el.textContent = patch.subject;
      });
    }
    if (patch.status) {
      const statusTd = row.querySelector('td.status');
      if (statusTd) statusTd.textContent = patch.status;
    }
    if (patch.tracker) {
      const trackerTd = row.querySelector('td.tracker');
      if (trackerTd) trackerTd.textContent = patch.tracker;
    }
    if (patch.priority) {
      const priorityTd = row.querySelector('td.priority');
      if (priorityTd) priorityTd.textContent = patch.priority;
    }
    if (Object.prototype.hasOwnProperty.call(patch, 'assigned_to')) {
      const assignedTd = row.querySelector('td.assigned_to');
      if (assignedTd) {
        assignedTd.textContent = isBlankAssigneeLabel(patch.assigned_to) ? '—' : patch.assigned_to;
      }
    }
    row.classList.add('backlog-row--flash');
    setTimeout(function () {
      row.classList.remove('backlog-row--flash');
    }, 1200);
  }

  function syncIssueSurfaces(issueId, patch) {
    if (!issueId || !patch || !Object.keys(patch).length) return;
    syncBacklogTicketNav(issueId, patch);
    syncBacklogTableRow(issueId, patch);
  }

  function setActiveTicketNav(issueId) {
    if (!issueId) return;
    if (backlogTicketNav) backlogTicketNav.currentId = String(issueId);

    const list = getTicketNavList();
    if (!list) return;

    const targetId = String(issueId);
    list.querySelectorAll('.ticket-nav__entry, .ticket-nav__item').forEach(function (el) {
      const btn = el.classList.contains('ticket-nav__item') ? el : el.querySelector('.ticket-nav__item');
      const id = btn ? String(btn.getAttribute('data-issue-id') || '') : '';
      const on = id === targetId;
      el.classList.toggle('is-active', on);
      if (el.classList.contains('ticket-nav__item')) {
        el.setAttribute('aria-current', on ? 'true' : 'false');
      }
    });

    const activeLi = list.querySelector('.ticket-nav__entry.is-active');
    if (activeLi) activeLi.scrollIntoView({ block: 'nearest' });
  }

  function hideBacklogTicketNav() {
    backlogTicketNav = null;
    modal.classList.remove('has-ticket-nav');
    const nav = getTicketNavShell();
    if (!nav) return;
    nav.hidden = true;
    const list = getTicketNavList();
    if (list) list.innerHTML = '';
  }

  function renderBacklogTicketNav() {
    const nav = getTicketNavShell();
    const list = getTicketNavList();
    const sectionEl = getTicketNavSectionEl();
    const countEl = getTicketNavCountEl();
    if (!nav || !list || !backlogTicketNav) return;

    sectionEl.textContent = backlogTicketNav.sectionLabel || 'Backlog';
    countEl.textContent = backlogTicketNav.tickets.length + ' tickets';
    list.innerHTML = backlogTicketNav.tickets.map(function (t) {
      const isActive = String(t.id) === String(backlogTicketNav.currentId);
      const id = escapeHtml(t.id);
      return (
        '<li class="ticket-nav__entry' + (isActive ? ' is-active' : '') + '" data-issue-id="' + id + '">' +
          '<button type="button" class="ticket-nav__item' + (isActive ? ' is-active' : '') + '" data-issue-id="' + id + '" aria-current="' + (isActive ? 'true' : 'false') + '"' +
            ' onclick="return window.SANAN_selectBacklogTicket && window.SANAN_selectBacklogTicket(\'' + id + '\', event)">' +
            '<span class="ticket-nav__top">' +
              '<span class="ticket-nav__id">#' + id + '</span>' +
              (t.status ? '<span class="ticket-nav__status">' + escapeHtml(t.status) + '</span>' : '') +
            '</span>' +
            '<span class="ticket-nav__subject">' + escapeHtml(t.subject) + '</span>' +
          '</button>' +
        '</li>'
      );
    }).join('');

    nav.hidden = backlogTicketNav.tickets.length === 0;
    modal.classList.toggle('has-ticket-nav', !nav.hidden);
    setActiveTicketNav(backlogTicketNav.currentId);
  }

  function showBacklogTicketNav(fromRow, issueId) {
    const collected = collectBacklogTickets(fromRow);
    backlogTicketNav = {
      sectionLabel: collected.sectionLabel,
      tickets: collected.tickets,
      currentId: String(issueId)
    };
    renderBacklogTicketNav();
  }

  function selectBacklogTicket(issueId, opts) {
    opts = opts || {};
    issueId = String(issueId || '');
    if (!issueId || !backlogTicketNav) return false;

    const same = issueId === String(backlogTicketNav.currentId);
    setActiveTicketNav(issueId);
    if (same && !opts.force) return true;

    isWasSubmitted = false;
    handleViewIssueModal(issueId);
    return true;
  }

  // Expose for inline onclick (most reliable across browsers)
  window.SANAN_selectBacklogTicket = function (issueId, event) {
    if (event) {
      event.preventDefault();
      event.stopPropagation();
      if (typeof event.stopImmediatePropagation === 'function') {
        event.stopImmediatePropagation();
      }
    }
    return selectBacklogTicket(issueId);
  };

  function onTicketNavClick(e) {
    const nav = e.target.closest && e.target.closest('#global-modal-ticket-nav');
    if (!nav) return;
    const btn = e.target.closest('.ticket-nav__item, .ticket-nav__entry');
    if (!btn || !backlogTicketNav) return;

    const issueId = btn.getAttribute('data-issue-id');
    if (!issueId) return;

    e.preventDefault();
    e.stopPropagation();
    if (typeof e.stopImmediatePropagation === 'function') e.stopImmediatePropagation();

    selectBacklogTicket(issueId);
  }

  function initBacklogTicketNav() {
    // Always (re)bind — clear stale flag from older script loads
    if (window.__sananTicketNavClickHandler) {
      document.removeEventListener('click', window.__sananTicketNavClickHandler, true);
    }
    window.__sananTicketNavClickHandler = onTicketNavClick;
    document.addEventListener('click', onTicketNavClick, true);
  }

  function closeModalWithReload() {
    closeModal()
    location.reload()
  }

  function extractToolbarInfo(scriptContent) {
    const elementIdMatch = scriptContent.match(/new\s+jsToolBar\s*\(\s*document\.getElementById\s*\(\s*['"]([^'"]+)['"]\s*\)\s*\)/);
    const helpLinkMatch = scriptContent.match(/\.setHelpLink\s*\(\s*['"]([^'"]+)['"]\s*\)/);
    const previewUrlMatch = scriptContent.match(/\.setPreviewUrl\s*\(\s*['"]([^'"]+)['"]\s*\)/);

    return {
      elementId: elementIdMatch?.[1] || null,
      helpLink: helpLinkMatch?.[1] || null,
      previewUrl: previewUrlMatch?.[1] || null
    };
  }

  function initWikiToolBar(textAreaElementId, helpLink, previewUrl) {
    var wikiToolbar = new jsToolBar(
      document.getElementById(textAreaElementId)
    );
    wikiToolbar.setHelpLink(
      helpLink
    );
    wikiToolbar.setPreviewUrl(
      previewUrl
    );
    wikiToolbar.draw();
  }

  function initPreviewToolbar() {
    $('#global-modal').on('click', 'div.jstTabs a.tab-preview', function (event) {
      var tab = $(event.target);

      var url = tab.data('url');
      var form = tab.parents('form');
      var jstBlock = tab.parents('.jstBlock');

      var element = encodeURIComponent(jstBlock.find('.wiki-edit').val());
      var attachments = form.find('.attachments_fields input').serialize();

      $.ajax({
        url: url,
        type: 'post',
        data: "text=" + element + '&' + attachments,
        success: function (data) {
          jstBlock.find('.wiki-preview').html(data);
          setupWikiTableSortableHeader();
        }
      });
    });
  }

  function initBtnScrollTop() {
    // Hiện/ẩn nút khi scroll xuống
    modalBody.addEventListener('scroll', () => {
      if (modalBody.scrollTop > 300) {
        scrollBtn.classList.add('show');
      } else {
        scrollBtn.classList.remove('show');
      }
    });

    // Cuộn lên đầu khi bấm nút
    scrollBtn.addEventListener('click', () => {
      modalBody.scrollTo({
        top: 0,
        behavior: 'smooth'
      });
    });
  }

  function initCloseBtn() {
    closeButton.addEventListener('click', function () {
      modalBody.innerHTML = "";
      // Nếu isCloseModalAfterSubmit=true => đã reload rồi
      if (isHotReload && isWasSubmitted) {
        return closeModalWithReload()
      }

      return closeModal()
    });
  }

  function openModal(title, content) {
    ScrollLock.lock();

    modalTitle.innerHTML = title

    const tempDiv = document.createElement('div');
    tempDiv.innerHTML = content;

    const statusSelect = tempDiv.querySelector('#issue_status_id');

    // Lấy ra value đang được chọn (là id của status)
    if (action !== Action.CREATE_SUB_TASK) {
      currentStatusId = statusSelect?.value;
    }

    const wikiToolBarInfos = []
    const scripts = tempDiv.querySelectorAll('script');
    scripts.forEach(tag => {
      if (tag.textContent && tag.textContent.includes('var wikiToolbar = new jsToolBar')) {
        wikiToolBarInfos.push(extractToolbarInfo(tag.textContent))
      }
    });

    // Xoá chrome / nested modal trước khi đưa vào DOM chính
    tempDiv.querySelector('#top-menu')?.remove();
    tempDiv.querySelector('#header')?.remove();
    tempDiv.querySelector('#footer')?.remove();
    tempDiv.querySelectorAll('#global-modal, #global-modal-ticket-nav').forEach(function (el) {
      el.remove();
    });
    tempDiv.querySelectorAll('script[src*="sanan_global_modal"]').forEach(function (el) {
      el.remove();
    });
    tempDiv.querySelectorAll('#history ul li a').forEach(item => {
      item.href = ""
    })
    const historyContent = tempDiv.querySelector("#tab-content-history")
    if (historyContent) {
      historyContent.style.display = "block"
    }

    // Chỉ lấy #main/#content để tránh nhét layout + modal lồng vào content body
    // (modal lồng làm getElementById trúng list ẩn → active không đổi trên sidebar thật)
    const mainEl = tempDiv.querySelector('#main');
    const contentEl = tempDiv.querySelector('#content');
    if (mainEl) {
      modalBody.innerHTML = '';
      modalBody.appendChild(mainEl);
    } else if (contentEl) {
      modalBody.innerHTML = '';
      modalBody.appendChild(contentEl);
    } else {
      modalBody.innerHTML = tempDiv.innerHTML;
    }

    modal.style.display = "flex";
    scrollBtn.classList.remove('show');

    requestAnimationFrame(() => {
      modalBody.scrollTop = 0;
    });

    modalBody.querySelectorAll('input[type=submit][data-disable-with]').forEach(btn => {
      btn.addEventListener('click', (e) => {
        const btnValue = e.target.value
        submitFormType = btnValue
      });
    });

    // Có thể bỏ khi auto load script, .... vào document hoat dong
    if (!window.wikiImageMimeTypes) {
      window.wikiImageMimeTypes = ["image/gif", "image/jpeg", "image/png", "image/tiff", "image/x-ms-bmp"]
    }
    if (!window.userHlLanguages) {
      window.userHlLanguages = ["c", "cpp", "csharp", "css", "diff", "go", "groovy", "html", "java", "javascript", "objc", "perl", "php", "python", "r", "ruby", "sass", "scala", "shell", "sql", "swift", "xml", "yaml"];
    }

    // 1. Đăng ký lại target cho sự kiện paste
    const timeout = setTimeout(() => {
      if (typeof jsToolBar !== 'undefined') {
        wikiToolBarInfos.forEach(info => {
          initWikiToolBar(info.elementId, info.helpLink, info.previewUrl)
        })
      }

      // Khởi tạo lại xử lý file drop/paste
      if (typeof setupFileDrop === 'function') {
        setupFileDrop();
      }

      initIssueTagsInModal();

      clearTimeout(timeout)
    }, 0);
  }

  function setErrorModal() {
    modalBody.innerHTML = "Có lỗi xảy ra"
  }

  function handleViewAfterSubmit(issueId) {
    if (action === Action.CREATE) {
      if (submitFormType === SubmitFormType.CREATE_AND_FOLLOW) {
        handleViewIssueModal(issueId)
      }

      return handleViewIssueModal(issueId)
    }

    if (action === Action.CREATE_SUB_TASK) {
      if (submitFormType === SubmitFormType.CREATE_AND_ADD_ANOTHER) {
        return handleCreateIssueModal()
      }

      return handleViewIssueModal(issueId)
    }

    if (action === Action.VIEW) {
      return handleViewIssueModal(issueId)
    }

    return handleViewIssueModal(issueId)
  }

  function handleViewIssueModal(issueId) {
    action = Action.VIEW
    const seq = ++viewRequestSeq;
    setActiveTicketNav(issueId);
    return fetch(`/issues/${issueId}`)
      .then((res) => res.text())
      .then((html) => {
        if (seq !== viewRequestSeq) return;
        openModal("View Issue", html)
        syncIssueSurfaces(issueId, parseIssueFieldsFromHtml(html));
        setActiveTicketNav(issueId);
      });
  }

  function handleCreateIssueModal() {
    action = Action.CREATE
    fetch(`/projects/${getProjectId()}/issues/new`)
      .then((res) => res.text())
      .then((html) => {
        openModal("Create Issue", html)
      });
  }

  function handleCreateSubIssueModal(parentIssueId) {
    action = Action.CREATE_SUB_TASK
    fetch(`/projects/${getProjectId()}/issues/new?back_url=/issues/${parentIssueId}&issue[parent_issue_id]=${parentIssueId}`)
      .then((res) => res.text())
      .then((html) => {
        openModal("Create Issue", html)
      });
  }

  function handleEditIssueModal(issueId) {
    action = Action.UPDATE
    fetch(`/issues/${issueId}/edit`, {
      headers: { "X-Requested-With": "XMLHttpRequest" }
    })
      .then(response => response.text())
      .then(html => {
        openModal("Edit Issue", html)
      });
  }

  initPreviewToolbar()
  initBtnScrollTop()
  initCloseBtn()
  initBacklogTicketNav()

  // handle view modal by action
  document.body.addEventListener("click", function (e) {
    // reset
    const isAgileBoardEditIssueBtn = e.target.closest(".edit-issue-link");
    const isAgileBoardCreateIssueBtn = e.target.closest("#new-agile-issue-btn");
    const isAgileBoardViewIssueByName = e.target.closest('.issue-card p.name a');

    const isListIssuesEditBtn = e.target.closest("#context-menu a.icon-edit");
    const isListIssuesCreateBtn = e.target.closest("a.icon-add.new-issue")

    const isCreateSubTaskBtn = e.target.closest('#global-modal #issue_tree .contextual a');
    const formEditRelation = e.target.closest('#global-modal #relations form')
    const isCreateRelationBtn = e.target.closest('#global-modal #relations input[type="submit"]')
    const isParentIssueInViewIssue = e.target.closest('#global-modal .subject a.issue')

    const isParentIssueInIssueCard = e.target.closest('.issue-card .sanan-attrs a.sanan-parent-pill')
    const isRelatedIssueInIssueCard = e.target.closest('.issue-card .attributes .rel-relates a.issue')

    const isReleaseIssueName = e.target.closest('.release-main .wi-table .wi-row .wi-summary')
    const isReleaseEpicName = e.target.closest('.release-main .wi-table .wi-row .wi-epic')
    const isBacklogIssueLink = e.target.closest('.sanan-backlog .backlog-row .backlog-issue-link')
    const isModalEditBtn = e.target.closest('#global-modal a.icon-edit')

    console.log("kaka", isReleaseIssueName)
    const getIssueId = () => {
      if (isModalEditBtn) {
        const href = isModalEditBtn.getAttribute('href') || ''
        const m = href.match(/\/issues\/(\d+)/)
        if (m) return m[1]
        return backlogTicketNav ? backlogTicketNav.currentId : null
      }

      if (isAgileBoardEditIssueBtn) {
        return isAgileBoardEditIssueBtn.dataset.issueId
      }

      if (isAgileBoardViewIssueByName) {
        const hrefArr = isAgileBoardViewIssueByName.getAttribute("href").split('/')
        return hrefArr[2]
      }

      if (isListIssuesEditBtn && isListIssuesEditBtn.getAttribute("href")?.includes("/issues")) {
        const hrefArr = isListIssuesEditBtn.getAttribute("href").split('/')
        return hrefArr[2]
      }

      if (isParentIssueInViewIssue && isParentIssueInViewIssue.getAttribute("href")?.includes("/issues")) {
        const hrefArr = isParentIssueInViewIssue.getAttribute("href").split('/')
        return hrefArr[2]
      }

      if (isCreateSubTaskBtn) {
        const hrefArr = isCreateSubTaskBtn.getAttribute("href").split('&')
        const parentIssueQuery = hrefArr[1].split('=')
        return parentIssueQuery[1]
      }

      if (formEditRelation) {
        const action = formEditRelation.getAttribute("action").split('/')
        return action[2]
      }

      if (isParentIssueInIssueCard) {
        const hrefArr = isParentIssueInIssueCard.getAttribute("href").split('/')
        return hrefArr[2]
      }

      if (isRelatedIssueInIssueCard) {
        const hrefArr = isRelatedIssueInIssueCard.getAttribute("href").split('/')
        return hrefArr[2]
      }

      if (isReleaseIssueName) {
        const row = isReleaseIssueName.closest('.wi-row')
        if (!row) null

        return row.dataset.id
      }

      if (isReleaseEpicName) {
        const row = isReleaseEpicName.closest('.wi-row')
        if (!row) null

        return row.dataset.epicId
      }

      if (isBacklogIssueLink) {
        const row = isBacklogIssueLink.closest('.backlog-row')
        return row ? row.dataset.id : null
      }

      return null
    }

    // Edit trong View Issue modal
    if (isModalEditBtn) {
      e.preventDefault();
      isWasSubmitted = false;
      const issueId = getIssueId();
      if (issueId) handleEditIssueModal(issueId);
      return;
    }

    if (isListIssuesCreateBtn && isListIssuesCreateBtn.getAttribute("href")?.includes("/projects")) {
      e.preventDefault();

      isHotReload = true;
      isWasSubmitted = false

      handleCreateIssueModal();
      return;
    }

    // Nếu là nút "Edit" từ context menu trong danh sách issue
    if (isListIssuesEditBtn && isListIssuesEditBtn.getAttribute("href")?.includes("/issues")) {
      e.preventDefault();

      isHotReload = true;
      isWasSubmitted = false

      handleEditIssueModal(getIssueId());
      return;
    }

    if (isAgileBoardViewIssueByName) {
      e.preventDefault();

      isWasSubmitted = false

      handleViewIssueModal(getIssueId())
      return;
    }

    if (isAgileBoardCreateIssueBtn) {
      e.preventDefault();

      isWasSubmitted = false

      handleCreateIssueModal()
      return;
    }

    // Nếu là từ Agile board
    if (isAgileBoardEditIssueBtn) {
      e.preventDefault();

      isWasSubmitted = false

      handleEditIssueModal(getIssueId());
      return;
    }

    if (isParentIssueInIssueCard) {
      e.preventDefault()

      isWasSubmitted = false

      handleViewIssueModal(getIssueId());
      return;
    }

    if (isRelatedIssueInIssueCard) {
      e.preventDefault()

      isWasSubmitted = false

      handleViewIssueModal(getIssueId());
      return;
    }

    if (isParentIssueInViewIssue) {
      e.preventDefault();

      isWasSubmitted = false

      handleViewIssueModal(getIssueId())
      return;
    }

    if ((window.location.pathname.includes('agile/board') || window.location.pathname.includes('/releases/')) && isCreateSubTaskBtn) {
      e.preventDefault();

      isWasSubmitted = false

      handleCreateSubIssueModal(getIssueId())
      return;
    }

    if (window.location.pathname.includes('agile/board') && isCreateRelationBtn) {
      const timeout = setTimeout(() => {
        if (window.SANAN_refreshIssueCard && getIssueId()) {
          const queryId = new URLSearchParams(location.search).get('query_id') || undefined;
          window.SANAN_refreshIssueCard(getIssueId(), {
            projectId: getProjectId(),
            queryId,
            statusId: currentStatusId,
            currentStatusId,
            scrollIntoView: true,  // cuộn tới card sau khi cập nhật
            highlight: true        // hiệu ứng nháy nhẹ
          });
          clearTimeout(timeout)
        }
      }, 500)
    }

    if (window.location.pathname.includes('/releases/')) {
      if (!isReleaseIssueName && !isReleaseEpicName) {
        return;
      }
      const issueId = getIssueId()
      if (!issueId) {
        return;
      }

      e.preventDefault();

      isWasSubmitted = false

      handleViewIssueModal(getIssueId())
      return;
    }

    if (window.location.pathname.includes('/backlog')) {
      if (!isBacklogIssueLink) {
        return;
      }
      const issueId = getIssueId()
      if (!issueId) {
        return;
      }

      e.preventDefault();
      isWasSubmitted = false
      const row = isBacklogIssueLink.closest('.backlog-row')
      showBacklogTicketNav(row, issueId)
      handleViewIssueModal(issueId)
      return;
    }
  });

  // handle submit form in modal
  document.addEventListener("submit", function (e) {
    const modal = e.target.closest(`#${globalModalElementId}`);
    if (modal) {
      e.preventDefault();

      isWasSubmitted = true;

      const form = e.target;

      const queryId = new URLSearchParams(location.search).get('query_id') || undefined;
      const projectId =
        form.querySelector('#issue_project_id')?.value ||
        document.querySelector('meta[name="current-project-id"]')?.content ||
        undefined;

      // helper: đoán có phải create không
      const isCreate = form.method.toUpperCase() === 'POST' &&
        /\/issues(\.json)?$/.test(new URL(form.action, location.origin).pathname);

      const headers = { 'X-Requested-With': 'XMLHttpRequest' };
      if (isCreate) headers['Accept'] = 'application/json';

      const formData = new FormData(form)
      let statusId = formData.get('issue[status_id]')

      if (submitFormType === SubmitFormType.CREATE_AND_FOLLOW) {
        formData.append("follow", SubmitFormType.CREATE_AND_FOLLOW)
      }

      if (action === Action.CREATE_SUB_TASK && submitFormType !== SubmitFormType.CREATE_AND_FOLLOW) {
        statusId = currentStatusId
      }

      fetch(form.action, {
        method: form.method,
        body: formData,
        headers: {
          'X-Requested-With': 'XMLHttpRequest'
        }
      }).then(async response => {
        if (response.ok) {
          if (isCreate) {
            const arrUrl = response.url.split('/')
            issueId = arrUrl[arrUrl.length - 1]
          } else {
            // update: có sẵn id trong action (/issues/:id)
            const m = form.action.match(/\/issues\/(\d+)/);
            issueId = m ? m[1] : form.querySelector('[name="issue[id]"]')?.value;
          }

          if (window.location.pathname.includes('/releases/') && action === Action.VIEW) {
            return location.reload()
          }

          const formPatch = extractIssuePatchFromForm(form);
          if (issueId) syncIssueSurfaces(issueId, formPatch);

          if (window.SANAN_refreshIssueCard && issueId) {
            await window.SANAN_refreshIssueCard(issueId, {
              projectId,
              queryId,
              statusId,
              currentStatusId,
              scrollIntoView: true,  // cuộn tới card sau khi cập nhật
              highlight: true        // hiệu ứng nháy nhẹ
            });
          }

          handleViewAfterSubmit(issueId)
        } else {
          throw new Error("response status not ok")
        }
      }).catch(error => {
        console.error(error);
        setErrorModal();
      });
    }
  });

}
