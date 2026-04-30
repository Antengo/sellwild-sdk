<template>
  <div class="arch-diagram">
    <div class="arch-row">
      <!-- Your App -->
      <div class="arch-node">
        <div class="node-header">
          <span class="node-title">Your App</span>
        </div>
        <div class="node-detail">iOS / Android / RN / Flutter</div>
      </div>

      <div class="arch-arrow">
        <div class="arrow-line"></div>
        <div class="arrow-label">1 SDK</div>
      </div>

      <!-- Sellwild SDK -->
      <div class="arch-node node-sdk">
        <div class="node-header">
          <span class="node-title">Sellwild SDK</span>
          <span class="node-badge active">Native</span>
        </div>
        <div class="node-items">
          <div class="node-item">
            <span class="item-dot green"></span>
            <span>Ad Views</span>
            <span class="item-meta">banner, MREC, video</span>
          </div>
          <div class="node-item">
            <span class="item-dot green"></span>
            <span>Listing Cards</span>
            <span class="item-meta">marketplace</span>
          </div>
          <div class="node-item">
            <span class="item-dot blue"></span>
            <span>Event Tracking</span>
            <span class="item-meta">impressions, clicks</span>
          </div>
        </div>
      </div>

      <div class="arch-arrow">
        <div class="arrow-line"></div>
        <div class="arrow-label">&lt; 200ms</div>
      </div>

      <!-- Prebid Server -->
      <div class="arch-node">
        <div class="node-header">
          <span class="node-title">Prebid Server</span>
          <span class="node-badge active">Live</span>
        </div>
        <div class="node-detail">prebid.sellwild.com</div>
        <div class="node-detail sub">S2S OpenRTB auction</div>
      </div>
    </div>

    <!-- SSP Section -->
    <div class="arch-ssp-section">
      <div class="ssp-connector"></div>
      <div class="ssp-label">
        <span>SSP Demand</span>
        <span class="node-badge count">400+</span>
      </div>
      <div class="ssp-grid">
        <div class="ssp-chip" v-for="ssp in ssps" :key="ssp">
          <span class="ssp-dot"></span>
          <span>{{ ssp }}</span>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
const ssps = [
  'AppNexus/Xandr', 'PubMatic', 'Magnite/Rubicon', 'Index Exchange',
  'OpenX', 'TripleLift', 'Sharethrough', 'InMobi',
  'Smaato', 'Yieldmo', 'Taboola', 'Media.net',
  'Sovrn', 'Unruly', 'LoopMe', 'Nativo',
]
</script>

<style scoped>
.arch-diagram {
  margin: 24px 0;
  padding: 32px;
  background: var(--vp-c-bg-alt);
  border: 1px solid var(--vp-c-border);
  border-radius: 16px;
  overflow-x: auto;
}

.arch-row {
  display: flex;
  align-items: center;
  gap: 0;
  justify-content: center;
}

.arch-node {
  background: var(--vp-c-bg-elv);
  border: 1px solid var(--vp-c-border);
  border-radius: 12px;
  padding: 14px 16px;
  min-width: 0;
  flex: 1;
  max-width: 220px;
}

.node-sdk {
  max-width: 240px;
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

.node-badge.count {
  background: var(--vp-c-brand-soft);
  color: var(--vp-c-text-1);
}

.node-detail {
  font-size: 12px;
  color: var(--vp-c-text-3);
}

.node-detail.sub {
  font-size: 11px;
  margin-top: 2px;
}

.node-items {
  margin-top: 10px;
  display: flex;
  flex-direction: column;
  gap: 6px;
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

.item-meta {
  color: var(--vp-c-text-3);
  font-size: 11px;
  margin-left: auto;
}

/* Arrows */
.arch-arrow {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
  padding: 0 4px;
  flex-shrink: 0;
}

.arrow-line {
  width: 40px;
  height: 2px;
  background: var(--vp-c-border);
  position: relative;
}

.arrow-line::after {
  content: '';
  position: absolute;
  right: -1px;
  top: -4px;
  width: 0;
  height: 0;
  border-left: 6px solid var(--vp-c-border);
  border-top: 5px solid transparent;
  border-bottom: 5px solid transparent;
}

.arrow-label {
  font-size: 10px;
  font-weight: 600;
  color: var(--vp-c-text-3);
  white-space: nowrap;
}

/* SSP Section */
.arch-ssp-section {
  margin-top: 20px;
  padding-top: 20px;
  position: relative;
  display: flex;
  flex-direction: column;
  align-items: center;
}

.ssp-connector {
  width: 2px;
  height: 20px;
  background: var(--vp-c-border);
  position: absolute;
  top: 0;
  left: 50%;
}

.ssp-label {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 13px;
  font-weight: 700;
  color: var(--vp-c-text-2);
  margin-bottom: 12px;
  margin-top: 8px;
}

.ssp-grid {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  justify-content: center;
  max-width: 600px;
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
.dark .node-badge.active {
  background: #14532D;
  color: #86EFAC;
}

.dark .ssp-dot {
  background: #4ADE80;
}

/* Mobile */
@media (max-width: 768px) {
  .arch-diagram {
    padding: 20px 16px;
  }

  .arch-row {
    flex-direction: column;
    gap: 0;
  }

  .arch-node {
    max-width: 100%;
    width: 100%;
  }

  .node-sdk {
    max-width: 100%;
  }

  .arch-arrow {
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
