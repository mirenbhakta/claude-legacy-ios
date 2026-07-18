(function () {
  const BASE_URL =
    "https://assets-proxy.anthropic.com/claude-ai/v2/assets/v1";
//  const BASE_URL = window.location.href

  // Safari 16.4 (iOS 16.4) shipped native support for every ES2022+ feature
  // Claude's bundle uses today, including class static initialization blocks
  // — the reason this shim exists in the first place. On 16.4+, the transpiler
  // just adds latency and has known interop issues with Rolldown-bundled
  // modules (dependency graphs stall after the entry chunk, root stays empty).
  // Let the site run natively there.
  const parts = String(window.iosVersion || "").split(".").map(Number);
  const major = parts[0] || 0;
  const minor = parts[1] || 0;
  const nativeCapable = major > 16 || (major === 16 && minor >= 4);
  if (nativeCapable) {
    try {
      console.log("[patch] iOS " + major + "." + minor + " — skipping transpiler");
    } catch (_) {}
    return;
  }

  window.LegacyTranspiler.init({
    BASE_URL,
    runScript: (code) => {
      window.webkit.messageHandlers.patchScript.postMessage(code);
    },
    target: {
      platform: 'iOS',
      version: iosVersion
    }
  });

  const observer = new MutationObserver((mutations) => {
    for (const mutation of mutations) {
      for (const node of mutation.addedNodes) {
        if (node.tagName === "SCRIPT" && node.src && node.src.includes('index')) {
          node.type = "javascript/blocked";
          const src = node.src;
          window.LegacyTranspiler.loadCode(src)
        }
      }
    }
  });

  observer.observe(document.documentElement, {
    childList: true,
    subtree: true,
  });
})();
