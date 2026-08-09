<template>
  <div class="arch-diagram">
    <div class="arch-row">
      <!-- Mobile App -->
      <div class="arch-node">
        <div class="node-header">
          <span class="node-title">Mobile App</span>
        </div>
        <div class="node-detail">Sellwild SDK</div>
      </div>

      <div class="arch-arrow">
        <div class="arrow-line"></div>
        <div class="arrow-label">POST /openrtb2/auction</div>
      </div>

      <!-- Prebid Server -->
      <div class="arch-node node-wide">
        <div class="node-header">
          <span class="node-title">Prebid Server</span>
          <span class="node-badge active">Live</span>
        </div>
        <div class="node-detail">prebid.sellwild.com</div>
        <div class="node-items">
          <div class="node-item">
            <span class="step-num">5</span>
            <span>Apply floors</span>
          </div>
          <div class="node-item">
            <span class="step-num">5</span>
            <span>Enforce GDPR</span>
          </div>
          <div class="node-item">
            <span class="step-num">5</span>
            <span>Select winner(s)</span>
          </div>
        </div>
      </div>

      <div class="arch-arrow">
        <div class="arrow-line"></div>
        <div class="arrow-label">Parallel bids</div>
      </div>

      <!-- SSP Endpoints -->
      <div class="arch-node">
        <div class="node-header">
          <span class="node-title">SSP Endpoints</span>
          <span class="node-badge count">400+</span>
        </div>
        <div class="node-detail">AppNexus, PubMatic, etc.</div>
      </div>
    </div>

    <!-- Steps timeline -->
    <div class="steps-section">
      <div class="ssp-connector"></div>
      <div class="steps-grid">
        <div class="step" v-for="step in steps" :key="step.num">
          <span class="step-num">{{ step.num }}</span>
          <span class="step-text">{{ step.text }}</span>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
const steps = [
  { num: '1', text: 'Prebid Mobile builds the OpenRTB request natively (no WebView)' },
  { num: '2', text: 'POST single OpenRTB request (imp[], app{}, regs{})' },
  { num: '3', text: 'Server fans out parallel bid requests to each SSP' },
  { num: '4', text: 'SSPs return bids (or no-bid) within timeout window' },
  { num: '5', text: 'Server runs auction: floors, GDPR, winner selection' },
  { num: '6', text: 'Response with seatbid[] and responsetimemillis' },
  { num: '7', text: 'AdManagerBannerView renders the winning creative' },
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
  justify-content: center;
  gap: 0;
}

.arch-node {
  background: var(--vp-c-bg-elv);
  border: 1px solid var(--vp-c-border);
  border-radius: 12px;
  padding: 14px 16px;
  min-width: 0;
  flex: 1;
  max-width: 200px;
}

.node-wide { max-width: 240px; }

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

.node-items {
  margin-top: 10px;
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

/* Steps timeline */
.steps-section {
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

.steps-grid {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  justify-content: center;
  max-width: 640px;
  margin-top: 8px;
}

.step {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 5px 12px;
  background: var(--vp-c-bg-elv);
  border: 1px solid var(--vp-c-border);
  border-radius: 6px;
  font-size: 11px;
  color: var(--vp-c-text-2);
}

.step-num {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 18px;
  height: 18px;
  border-radius: 9px;
  background: var(--vp-c-brand-soft);
  color: var(--vp-c-text-1);
  font-size: 10px;
  font-weight: 700;
  flex-shrink: 0;
}

.step-text {
  color: var(--vp-c-text-2);
}

/* Dark mode */
.dark .node-badge.active {
  background: #14532D;
  color: #86EFAC;
}

/* Mobile */
@media (max-width: 768px) {
  .arch-diagram { padding: 20px 16px; }
  .arch-row { flex-direction: column; gap: 0; }
  .arch-node { max-width: 100%; width: 100%; }
  .node-wide { max-width: 100%; }

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

  .arrow-label { margin-top: 0; }
}
</style>
