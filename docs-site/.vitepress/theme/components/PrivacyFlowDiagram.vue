<template>
  <div class="arch-diagram">
    <!-- Device layer -->
    <div class="layer">
      <div class="layer-label">User's Device</div>

      <div class="layer-row">
        <div class="arch-node">
          <div class="node-header">
            <span class="node-title">Host App</span>
          </div>
          <div class="node-items">
            <div class="node-item">
              <span class="item-dot green"></span>
              <span>CMP collects consent</span>
            </div>
            <div class="node-item">
              <span class="item-dot green"></span>
              <span>TC string / GPP string / US Privacy</span>
            </div>
            <div class="node-item">
              <span class="item-dot blue"></span>
              <span>ATT prompt (iOS) — IDFA if authorized</span>
            </div>
          </div>
        </div>

        <div class="arch-node">
          <div class="node-header">
            <span class="node-title">Sellwild SDK</span>
            <span class="node-badge safe">No PII Stored</span>
          </div>
          <div class="node-items">
            <div class="node-item">
              <span class="item-dot green"></span>
              <span>Constructs OpenRTB bid request</span>
            </div>
            <div class="node-item">
              <span class="item-dot green"></span>
              <span>App identity + device info + consent</span>
            </div>
            <div class="node-item">
              <span class="item-dot green"></span>
              <span>NO personal data stored by SDK</span>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- What leaves the device -->
    <div class="data-section">
      <div class="connector-down"></div>
      <div class="data-label">What leaves the device</div>
      <div class="data-grid">
        <div class="data-chip" v-for="field in dataFields" :key="field.name">
          <code>{{ field.name }}</code>
          <span class="data-desc">{{ field.desc }}</span>
        </div>
      </div>
    </div>

    <!-- Arrow down -->
    <div class="vertical-arrow">
      <div class="v-arrow-line"></div>
    </div>

    <!-- Server layer -->
    <div class="layer">
      <div class="layer-label">
        <span>prebid.sellwild.com</span>
        <span class="node-badge active">Live</span>
      </div>

      <div class="layer-row">
        <div class="arch-node">
          <div class="node-header">
            <span class="node-title">Privacy Enforcement</span>
          </div>
          <div class="node-items">
            <div class="node-item">
              <span class="item-dot green"></span>
              <span>Checks regs.ext.gdpr</span>
            </div>
            <div class="node-item">
              <span class="item-dot green"></span>
              <span>Validates TC string vendor consent</span>
            </div>
            <div class="node-item">
              <span class="item-dot green"></span>
              <span>Suppresses non-consented bidders</span>
            </div>
            <div class="node-item">
              <span class="item-dot green"></span>
              <span>Forwards us_privacy / GPP to SSPs</span>
            </div>
          </div>
        </div>

        <div class="arch-node does-not-node">
          <div class="node-header">
            <span class="node-title">Does NOT</span>
            <span class="node-badge warn">Important</span>
          </div>
          <div class="node-items">
            <div class="node-item">
              <span class="item-dot red"></span>
              <span>Store user data</span>
            </div>
            <div class="node-item">
              <span class="item-dot red"></span>
              <span>Create user profiles</span>
            </div>
            <div class="node-item">
              <span class="item-dot red"></span>
              <span>Perform cross-session tracking</span>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- SSP row -->
    <div class="ssp-row">
      <div class="connector-down"></div>
      <div class="ssp-label">SSPs receive bid requests with consent signals</div>
      <div class="ssp-chips">
        <div class="ssp-chip" v-for="ssp in ssps" :key="ssp">
          <span class="ssp-dot"></span>
          <span>{{ ssp }}</span>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
const dataFields = [
  { name: 'app.bundle', desc: 'app ID' },
  { name: 'app.storeurl', desc: 'store listing' },
  { name: 'device.ua', desc: 'user agent' },
  { name: 'device.os', desc: 'OS version' },
  { name: 'imp[].banner.format', desc: 'ad sizes' },
  { name: 'regs.ext.gdpr', desc: '0 or 1' },
  { name: 'user.ext.consent', desc: 'TC string' },
  { name: 'regs.ext.us_privacy', desc: 'if set' },
  { name: 'regs.gpp', desc: 'if GPP enabled' },
  { name: 'device.ifa', desc: 'only if app passes' },
]

const ssps = ['AppNexus', 'PubMatic', 'IX']
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
}

.layer-row {
  display: flex;
  gap: 8px;
  justify-content: center;
  flex-wrap: wrap;
  width: 100%;
  max-width: 640px;
}

.layer-row .arch-node {
  flex: 1;
  min-width: 200px;
}

.arch-node {
  background: var(--vp-c-bg-elv);
  border: 1px solid var(--vp-c-border);
  border-radius: 12px;
  padding: 14px 16px;
}

.does-not-node {
  border-color: #FCA5A5;
}

.dark .does-not-node {
  border-color: #7F1D1D;
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

.node-badge.active { background: #DCFCE7; color: #166534; }
.node-badge.safe { background: #DBEAFE; color: #1D4ED8; }
.node-badge.warn { background: #FEF3C7; color: #92400E; }

.node-items {
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
.item-dot.red { background: #EF4444; }

/* Data fields section */
.data-section {
  display: flex;
  flex-direction: column;
  align-items: center;
  margin: 8px 0;
}

.connector-down {
  width: 2px;
  height: 16px;
  background: var(--vp-c-border);
}

.data-label {
  font-size: 11px;
  font-weight: 700;
  color: var(--vp-c-text-3);
  text-transform: uppercase;
  letter-spacing: 0.5px;
  margin: 8px 0;
}

.data-grid {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
  justify-content: center;
  max-width: 600px;
}

.data-chip {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 3px 10px;
  background: var(--vp-c-bg-elv);
  border: 1px solid var(--vp-c-border);
  border-radius: 6px;
  font-size: 11px;
}

.data-chip code {
  font-family: var(--vp-font-family-mono);
  font-size: 10px;
  font-weight: 600;
  color: var(--vp-c-text-1);
  background: none;
  padding: 0;
}

.data-desc {
  color: var(--vp-c-text-3);
  font-size: 10px;
}

/* Vertical arrow */
.vertical-arrow {
  display: flex;
  justify-content: center;
  padding: 4px 0;
}

.v-arrow-line {
  width: 2px;
  height: 20px;
  background: var(--vp-c-border);
  position: relative;
}

.v-arrow-line::after {
  content: '';
  position: absolute;
  bottom: -1px;
  left: 50%;
  transform: translateX(-50%);
  border-top: 6px solid var(--vp-c-border);
  border-left: 5px solid transparent;
  border-right: 5px solid transparent;
}

/* SSP row */
.ssp-row {
  display: flex;
  flex-direction: column;
  align-items: center;
  margin-top: 8px;
}

.ssp-label {
  font-size: 11px;
  color: var(--vp-c-text-3);
  margin: 8px 0;
}

.ssp-chips {
  display: flex;
  gap: 6px;
  justify-content: center;
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

.ssp-dot {
  width: 6px;
  height: 6px;
  border-radius: 3px;
  background: #22C55E;
}

/* Dark mode */
.dark .node-badge.active { background: #14532D; color: #86EFAC; }
.dark .node-badge.safe { background: #1E3A5F; color: #93C5FD; }
.dark .node-badge.warn { background: #451A03; color: #FCD34D; }
.dark .ssp-dot { background: #4ADE80; }

/* Mobile */
@media (max-width: 768px) {
  .arch-diagram { padding: 20px 16px; }
  .layer-row .arch-node { min-width: 0; }
}
</style>
