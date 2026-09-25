import type { SellwildConfig, AdSize } from '@sellwild/sdk-core'

// ─────────────────────────────────────────────────────────────────────────────
// Banner HTML builder
//
// Dead code, kept pending the owner's delete decision: no component, sample or
// doc in this repo calls buildBannerHtml (<SellwildBanner> is a native view
// since 1.3.0). It moved here from htmlBuilder.ts, which still re-exports it,
// so the coverage gate can exclude this file with that reason
// (vitest.config.ts coverageExclusions). Nothing else changed but the in-page
// catch, which no longer is empty (contracts/FAILURES.md 1).
// ─────────────────────────────────────────────────────────────────────────────
export function buildBannerHtml(
  config: SellwildConfig,
  zoneId: number | string,
  size: AdSize
): string {
  const [width, height] = size.split('x').map(Number)
  const gptSrc = config.gptProxyUrl
    ? `${config.gptProxyUrl}/tag/js/gpt.js`
    : 'https://securepubads.g.doubleclick.net/tag/js/gpt.js'

  const adScript = config.gamTag && !config.disableGpt
    ? buildGptScript(config.gamTag, gptSrc, width, height)
    : buildZoneScript(String(zoneId), width, height)

  return `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    html, body { width: ${width}px; height: ${height}px; overflow: hidden; background: transparent; }
    #ad { width: ${width}px; height: ${height}px; }
  </style>
</head>
<body>
  <div id="ad"></div>
  <script>
    function notify(type) {
      try { window.ReactNativeWebView.postMessage(JSON.stringify({ type: type })); } catch(e) { window.__sellwildBridgeFailures = (window.__sellwildBridgeFailures || 0) + 1; }
    }
    ${adScript}
  </script>
</body>
</html>`
}

function buildGptScript(gamTag: string, gptSrc: string, w: number, h: number): string {
  return `
    window.googletag = window.googletag || { cmd: [] };
    var s = document.createElement('script');
    s.src = '${gptSrc}'; s.async = true;
    document.head.appendChild(s);
    googletag.cmd.push(function() {
      var slot = googletag.defineSlot('${gamTag}', [${w}, ${h}], 'ad');
      if (slot) {
        slot.addService(googletag.pubads());
        googletag.pubads().enableSingleRequest();
        googletag.pubads().addEventListener('slotRenderEnded', function(e) {
          if (!e.isEmpty) notify('AD_IMPRESSION');
        });
        googletag.enableServices();
        googletag.display('ad');
      }
    });`
}

function buildZoneScript(zoneId: string, w: number, h: number): string {
  return `
    var s = document.createElement('script');
    s.src = 'https://bidstream.sellwild.com/ads?zone=${zoneId}&w=${w}&h=${h}';
    s.async = true;
    s.onload = function() { notify('AD_IMPRESSION'); };
    document.getElementById('ad').appendChild(s);`
}
