<template>
  <div class="arch-diagram">
    <!-- App layer -->
    <div class="layer">
      <div class="layer-label">
        <span>Your Mobile App</span>
      </div>

      <div class="layer-row">
        <div class="arch-node">
          <div class="node-header">
            <span class="node-title">SellwildAdView</span>
          </div>
          <div class="node-detail">banner, MREC, video, interstitial</div>
        </div>
        <div class="arch-node">
          <div class="node-header">
            <span class="node-title">SellwildWidget</span>
          </div>
          <div class="node-detail">listing carousel + embedded ads</div>
        </div>
        <div class="arch-node">
          <div class="node-header">
            <span class="node-title">API Client</span>
          </div>
          <div class="node-detail">listings fetch</div>
        </div>
      </div>

      <div class="connector-down"></div>

      <div class="arch-node webview-node">
        <div class="node-header">
          <span class="node-title">Managed WebView</span>
          <span class="node-badge muted">WKWebView / Android WebView</span>
        </div>
        <div class="node-items">
          <div class="node-item">
            <span class="item-dot blue"></span>
            <span>Prebid.js (S2S mode)</span>
          </div>
          <div class="node-item">
            <span class="item-dot green"></span>
            <span>ortb2.app signals injected</span>
          </div>
          <div class="node-item">
            <span class="item-dot green"></span>
            <span>iframe syncs disabled</span>
          </div>
          <div class="node-item">
            <span class="item-dot green"></span>
            <span>s2sConfig → prebid.sellwild.com</span>
          </div>
        </div>
      </div>
    </div>

    <!-- Arrow down -->
    <div class="vertical-arrow">
      <div class="v-arrow-line"></div>
      <div class="v-arrow-label">HTTPS POST /openrtb2/auction</div>
    </div>

    <!-- Server layer -->
    <div class="layer">
      <div class="layer-label">
        <span>prebid.sellwild.com</span>
        <span class="node-badge active">Live</span>
      </div>

      <div class="arch-node server-node">
        <div class="node-header">
          <span class="node-title">OpenRTB 2.6 Auction Engine</span>
        </div>
        <div class="node-items">
          <div class="node-item">
            <span class="item-dot green"></span>
            <span>Parse imp[], app{}, device{}, regs{}, user{}</span>
          </div>
          <div class="node-item">
            <span class="item-dot green"></span>
            <span>Enforce GDPR / TCF v2 vendor consent</span>
          </div>
          <div class="node-item">
            <span class="item-dot green"></span>
            <span>Apply bid floors</span>
          </div>
          <div class="node-item">
            <span class="item-dot blue"></span>
            <span>Fan out parallel bid requests to configured SSPs</span>
          </div>
          <div class="node-item">
            <span class="item-dot blue"></span>
            <span>Collect responses within timeout window</span>
          </div>
          <div class="node-item">
            <span class="item-dot green"></span>
            <span>Return seatbid[] with creative markup (adm)</span>
          </div>
        </div>
      </div>
    </div>

    <!-- SSP row -->
    <div class="ssp-row">
      <div class="connector-down"></div>
      <div class="ssp-chips">
        <div class="ssp-chip" v-for="ssp in ssps" :key="ssp">
          <span class="ssp-dot"></span>
          <span>{{ ssp }}</span>
        </div>
        <div class="ssp-chip ssp-more">
          <span>... 400+</span>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
const ssps = ['AppNexus', 'PubMatic', 'IX', 'Rubicon', 'OpenX']
</script>

<style scoped>
.arch-diagram {
  margin: 24px 0;
  padding: 32px 24px;
  background: var(--vp-c-bg-alt);
  border: 1px solid var(--vp-c-border);
  border-radius: 16px;
  overflow-x: auto;
}

.layer {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 10px;
}

.layer-label {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 13px;
  font-weight: 700;
  color: var(--vp-c-text-2);
  margin-bottom: 4px;
}

.layer-row {
  display: flex;
  gap: 8px;
  justify-content: center;
  flex-wrap: wrap;
}

.arch-node {
  background: var(--vp-c-bg-elv);
  border: 1px solid var(--vp-c-border);
  border-radius: 12px;
  padding: 14px 16px;
}

.layer-row .arch-node {
  flex: 1;
  max-width: 200px;
  min-width: 140px;
}

.webview-node {
  width: 100%;
  max-width: 640px;
}

.server-node {
  width: 100%;
  max-width: 640px;
}

.node-header {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 6px;
}

.node-title {
  font-weight: 700;
  font-size: 14px;
  color: var(--vp-c-text-1);
}

.node-badge {
  font-size: 10px;
  font-weight: 700;
  padding: 2px 8px;
  border-radius: 10px;
  letter-spacing: 0.5px;
}

.node-badge.active {
  background: #DCFCE7;
  color: #166534;
}

.node-badge.muted {
  background: var(--vp-c-brand-soft);
  color: var(--vp-c-text-3);
  font-weight: 500;
}

.node-detail {
  font-size: 12px;
  color: var(--vp-c-text-3);
}

.node-items {
  margin-top: 8px;
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.node-item {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  color: var(--vp-c-text-2);
}

.item-dot {
  width: 6px;
  height: 6px;
  border-radius: 3px;
  flex-shrink: 0;
}

.item-dot.green { background: #22C55E; }
.item-dot.blue { background: #3B82F6; }

/* Vertical connectors */
.connector-down {
  width: 2px;
  height: 16px;
  background: var(--vp-c-border);
  margin: 0 auto;
}

.vertical-arrow {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
  padding: 8px 0;
}

.v-arrow-line {
  width: 2px;
  height: 24px;
  background: var(--vp-c-border);
  position: relative;
}

.v-arrow-line::after {
  content: '';
  position: absolute;
  bottom: -1px;
  left: 50%;
  transform: translateX(-50%);
  width: 0;
  height: 0;
  border-top: 6px solid var(--vp-c-border);
  border-left: 5px solid transparent;
  border-right: 5px solid transparent;
}

.v-arrow-label {
  font-size: 10px;
  font-weight: 600;
  color: var(--vp-c-text-3);
  font-family: var(--vp-font-family-mono);
}

/* SSP row */
.ssp-row {
  display: flex;
  flex-direction: column;
  align-items: center;
  margin-top: 8px;
}

.ssp-chips {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  justify-content: center;
  margin-top: 8px;
}

.ssp-chip {
  display: flex;
  align-items: center;
  gap: 5px;
  padding: 4px 10px;
  background: var(--vp-c-bg-elv);
  border: 1px solid var(--vp-c-border);
  border-radius: 6px;
  font-size: 11px;
  font-weight: 500;
  color: var(--vp-c-text-2);
}

.ssp-more {
  color: var(--vp-c-text-3);
  font-style: italic;
}

.ssp-dot {
  width: 6px;
  height: 6px;
  border-radius: 3px;
  background: #22C55E;
}

/* Dark mode */
.dark .node-badge.active { background: #14532D; color: #86EFAC; }
.dark .ssp-dot { background: #4ADE80; }

/* Mobile */
@media (max-width: 768px) {
  .arch-diagram { padding: 20px 16px; }
  .layer-row .arch-node { max-width: 100%; min-width: 0; }
}
</style>
