document.getElementById('open-btn').addEventListener('click', async () => {
  if (typeof browser !== 'undefined' && browser.tabs) {
    const tabs = await browser.tabs.query({ active: true, currentWindow: true });
    if (tabs && tabs[0] && tabs[0].url) {
      window.location.href = 'audia://open?url=' + encodeURIComponent(tabs[0].url);
      return;
    }
  }
  window.location.href = 'audia://player';
});
