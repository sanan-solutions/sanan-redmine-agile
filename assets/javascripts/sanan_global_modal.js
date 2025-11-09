document.addEventListener("DOMContentLoaded", function () {
  // Handler cho Agile board
  const globalModalElementId = "global-modal"
  const modal = document.getElementById(globalModalElementId);
  const modalTitle = modal.querySelector(".header__title")
  const modalBody = modal.querySelector(".content__body");

  const closeButton = modal.querySelector('.header__close-btn');
  const scrollBtn = document.getElementById('modal-scroll-top');

  let currentStatusId = null; // TODO: luw parent current status
  let isHotReload = false;
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
    ScrollLock.unlock();
    modal.style.display = "none";
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

    // Xoá các phần tử không mong muốn trước khi đưa vào DOM chính
    tempDiv.querySelector('#top-menu')?.remove();
    tempDiv.querySelector('#header')?.remove();
    tempDiv.querySelectorAll('#history ul li a').forEach(item => {
      item.href = ""
    })
    const historyContent = tempDiv.querySelector("#tab-content-history")
    if (historyContent) {
      historyContent.style.display = "block"
    }

    // Sau khi lọc xong, gán vào modal container
    modalBody.innerHTML = tempDiv.innerHTML;

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
    fetch(`/issues/${issueId}`)
      .then((res) => res.text())
      .then((html) => {
        openModal("View Issue", html)
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

    console.log("kaka", isReleaseIssueName)
    const getIssueId = () => {
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

      return null
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

});

