<template>
  <div class="arch-container">
    <div class="flow-row">
      <div class="node">
        <div class="node-title">Your App</div>
        <div class="node-subtitle">iOS / Android / RN / Flutter</div>
      </div>

      <div class="arrow">
        <div class="arrow-line"></div>
        <div class="arrow-label">1 SDK</div>
      </div>

      <div class="node node-sdk">
        <div class="node-header">
          <div class="node-title">Sellwild SDK</div>
          <span class="node-badge active">Native</span>
        </div>
        <ul class="node-list">
          <li><strong>Ad Views</strong> <span class="dim">banner, MREC, video</span></li>
          <li><strong>Listing Cards</strong> <span class="dim">marketplace</span></li>
          <li><strong>Event Tracking</strong> <span class="dim">impressions, clicks</span></li>
        </ul>
      </div>

      <div class="arrow">
        <div class="arrow-line"></div>
        <div class="arrow-label">&lt; 200ms</div>
      </div>

      <div class="node">
        <div class="node-header">
          <div class="node-title">Prebid Server</div>
          <span class="node-badge active">Live</span>
        </div>
        <div class="node-subtitle">prebid.sellwild.com</div>
        <div class="node-detail">S2S OpenRTB auction</div>
      </div>
    </div>

    <div class="ssp-section">
      <div class="ssp-header">
        <span class="ssp-label">SSP Demand</span>
        <span class="node-badge active">400+</span>
      </div>
      <div class="ssp-grid">
        <span class="ssp-chip" v-for="ssp in ssps" :key="ssp">
          <span class="ssp-dot"></span>
          {{ ssp }}
        </span>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
const ssps = [
  'AppNexus/Xandr',
  'PubMatic',
  'Magnite/Rubicon',
  'Index Exchange',
  'OpenX',
  'TripleLift',
  'Sharethrough',
  'InMobi',
  'Smaato',
  'Yieldmo',
  'Taboola',
  'Media.net',
  'Sovrn',
  'Unruly',
  'LoopMe',
  'Nativo',
]
</script>

<style scoped>
.arch-container {
  background: var(--vp-c-bg-alt);
  border: 1px solid var(--vp-c-border);
  border-radius: 16px;
  padding: 32px 24px;
  margin: 24px 0;
  overflow: hidden;
}

.flow-row {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0;
}

.node {
  flex: 1;
  max-width: 220px;
  background: var(--vp-c-bg-elv);
  border: 1px solid var(--vp-c-border);
  border-radius: 12px;
  padding: 16px;
}

.node-sdk {
  max-width: 240px;
}

.node-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  margin-bottom: 4px;
}

.node-title {
  font-weight: 700;
  font-size: 14px;
  color: var(--vp-c-text-1);
}

.node-subtitle {
  font-size: 12px;
  color: var(--vp-c-text-3);
  margin-top: 4px;
}

.node-detail {
  font-size: 12px;
  color: var(--vp-c-text-2);
  margin-top: 2px;
}

.node-badge {
  display: inline-flex;
  align-items: center;
  font-size: 11px;
  font-weight: 600;
  padding: 2px 8px;
  border-radius: 9999px;
  white-space: nowrap;
}

.node-badge.active {
  background: #DCFCE7;
  color: #166534;
}

.node-list {
  list-style: none;
  margin: 10px 0 0;
  padding: 0;
}

.node-list li {
  font-size: 12px;
  color: var(--vp-c-text-2);
  padding: 3px 0;
  border-top: 1px solid var(--vp-c-border);
}

.node-list li:first-child {
  border-top: none;
}

.node-list strong {
  color: var(--vp-c-text-1);
  font-weight: 600;
}

.dim {
  color: var(--vp-c-text-3);
}

/* Arrows */
.arrow {
  display: flex;
  flex-direction: column;
  align-items: center;
  width: 60px;
  flex-shrink: 0;
}

.arrow-line {
  position: relative;
  width: 40px;
  height: 2px;
  background: var(--vp-c-border);
}

.arrow-line::after {
  content: '';
  position: absolute;
  right: -1px;
  top: 50%;
  transform: translateY(-50%);
  width: 0;
  height: 0;
  border-top: 5px solid transparent;
  border-bottom: 5px solid transparent;
  border-left: 7px solid var(--vp-c-border);
}

.arrow-label {
  font-size: 10px;
  font-weight: 600;
  color: var(--vp-c-text-3);
  margin-top: 4px;
  white-space: nowrap;
}

/* SSP Section */
.ssp-section {
  margin-top: 24px;
  padding-top: 20px;
  border-top: 1px solid var(--vp-c-border);
}

.ssp-header {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 12px;
}

.ssp-label {
  font-weight: 700;
  font-size: 14px;
  color: var(--vp-c-text-1);
}

.ssp-grid {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.ssp-chip {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  font-weight: 500;
  color: var(--vp-c-text-2);
  background: var(--vp-c-bg-elv);
  border: 1px solid var(--vp-c-border);
  border-radius: 8px;
  padding: 4px 10px;
}

.ssp-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: #22C55E;
  flex-shrink: 0;
}

/* Dark mode */
.dark .node-badge.active {
  background: #14532D;
  color: #86EFAC;
}

/* Mobile responsive */
@media (max-width: 768px) {
  .arch-container {
    padding: 20px 16px;
  }

  .flow-row {
    flex-direction: column;
    gap: 0;
  }

  .node {
    max-width: 100%;
    width: 100%;
  }

  .node-sdk {
    max-width: 100%;
  }

  .arrow {
    width: auto;
    height: 40px;
    flex-direction: row;
    gap: 8px;
  }

  .arrow-line {
    width: 2px;
    height: 24px;
  }

  .arrow-line::after {
    right: auto;
    left: 50%;
    top: auto;
    bottom: -1px;
    transform: translateX(-50%);
    border-top: 7px solid var(--vp-c-border);
    border-left: 5px solid transparent;
    border-right: 5px solid transparent;
    border-bottom: none;
  }

  .arrow-label {
    margin-top: 0;
  }
}
</style>
