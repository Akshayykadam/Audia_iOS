(function () {
  'use strict';

  // Prevent multiple injections
  if (window.hasAudiaInjected) return;
  window.hasAudiaInjected = true;

  function getAudiaUrl(currentUrl) {
    return 'audia://open?url=' + encodeURIComponent(currentUrl || window.location.href);
  }

  function openInAudia(url) {
    const target = getAudiaUrl(url);
    window.location.href = target;
  }

  function injectBanner() {
    if (document.getElementById('audia-banner-container')) return;

    const container = document.createElement('div');
    container.id = 'audia-banner-container';

    container.innerHTML = `
      <div class="audia-banner" id="audia-tap-area">
        <div class="audia-left">
          <div class="audia-icon">▶</div>
          <div class="audia-text">
            <span class="audia-title">Open in Audia</span>
            <span class="audia-subtitle">Listen ad-free with background playback</span>
          </div>
        </div>
        <div class="audia-right">
          <button class="audia-btn" id="audia-open-btn">Open</button>
          <button class="audia-close" id="audia-close-btn" aria-label="Close">✕</button>
        </div>
      </div>
    `;

    document.documentElement.appendChild(container);

    const tapArea = document.getElementById('audia-tap-area');
    const openBtn = document.getElementById('audia-open-btn');
    const closeBtn = document.getElementById('audia-close-btn');

    function handleOpen(e) {
      e.stopPropagation();
      openInAudia();
    }

    if (tapArea) tapArea.addEventListener('click', handleOpen);
    if (openBtn) openBtn.addEventListener('click', handleOpen);

    if (closeBtn) {
      closeBtn.addEventListener('click', function (e) {
        e.stopPropagation();
        container.remove();
      });
    }
  }

  // Attempt automatic trigger via hidden link if opened freshly
  try {
    const path = window.location.pathname;
    const search = window.location.search;
    if (path.includes('watch') || search.includes('list=') || path.includes('browse') || path.includes('playlist')) {
      const a = document.createElement('a');
      a.href = getAudiaUrl();
      a.style.display = 'none';
      document.documentElement.appendChild(a);
      a.click();
      a.remove();
    }
  } catch (e) {
    // Handled by user tapping the banner
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', injectBanner);
  } else {
    injectBanner();
  }

  // Handle YouTube SPA URL changes
  window.addEventListener('yt-navigate-finish', function () {
    injectBanner();
  });

  let lastUrl = location.href;
  new MutationObserver(() => {
    const url = location.href;
    if (url !== lastUrl) {
      lastUrl = url;
      injectBanner();
    }
  }).observe(document, { subtree: true, childList: true });
})();
