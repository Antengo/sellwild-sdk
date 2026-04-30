<template>
  <div class="arch-diagram">
    <!-- Column headers -->
    <div class="flow-headers">
      <div class="flow-col-header" v-for="col in columns" :key="col">{{ col }}</div>
    </div>

    <!-- Steps -->
    <div class="flow-steps">
      <div class="flow-step" v-for="step in steps" :key="step.num" :class="'from-' + step.from + ' to-' + step.to">
        <div class="step-indicator">
          <span class="step-num">{{ step.num }}</span>
        </div>
        <div class="step-content">
          <div class="step-action">{{ step.action }}</div>
          <div class="step-detail" v-if="step.detail">{{ step.detail }}</div>
        </div>
        <div class="step-direction">
          <span class="dir-badge" :class="step.dir">{{ step.dirLabel }}</span>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
const columns = ['App', 'SDK WebView', 'Prebid Server', 'SSPs']

const steps = [
  { num: '1', from: 'app', to: 'sdk', action: 'load()', detail: 'App triggers ad request', dir: 'right', dirLabel: '→' },
  { num: '2', from: 'sdk', to: 'sdk', action: 'Build HTML', detail: 's2sConfig, ortb2.app, userSync filters', dir: 'self', dirLabel: '⟳' },
  { num: '3', from: 'sdk', to: 'sdk', action: 'Load Prebid.js', detail: 'From CDN or custom prebidSrc URL', dir: 'self', dirLabel: '⟳' },
  { num: '4', from: 'sdk', to: 'pbs', action: 'POST /openrtb2/auction', detail: 'imp[], app{}, device{}, regs{}, tmax', dir: 'right', dirLabel: '→' },
  { num: '5', from: 'pbs', to: 'ssp', action: 'Parallel bid requests', detail: 'Fan out to each configured SSP', dir: 'right', dirLabel: '→' },
  { num: '6', from: 'ssp', to: 'pbs', action: 'Bids returned', detail: 'Or no-bid, within timeout window', dir: 'left', dirLabel: '←' },
  { num: '7', from: 'pbs', to: 'pbs', action: 'Run auction', detail: 'Apply floors, enforce consent, pick winner(s)', dir: 'self', dirLabel: '⟳' },
  { num: '8', from: 'pbs', to: 'sdk', action: 'BidResponse', detail: 'seatbid[], ext{}', dir: 'left', dirLabel: '←' },
  { num: '9', from: 'sdk', to: 'sdk', action: 'Render creative', detail: 'Winning adm in WebView ad slot', dir: 'self', dirLabel: '⟳' },
  { num: '10', from: 'sdk', to: 'app', action: 'AD_LOADED callback', detail: 'JS bridge fires', dir: 'left', dirLabel: '←' },
  { num: '11', from: 'sdk', to: 'sdk', action: 'Impression pixel fires', detail: 'Viewability tracking', dir: 'self', dirLabel: '⟳' },
  { num: '12', from: 'sdk', to: 'app', action: 'AD_IMPRESSION callback', detail: 'JS bridge fires', dir: 'left', dirLabel: '←' },
]
</script>

<style scoped>
.arch-diagram {
  margin: 24px 0;
  padding: 24px;
  background: var(--vp-c-bg-alt);
  border: 1px solid var(--vp-c-border);
  border-radius: 16px;
  overflow-x: auto;
}

.flow-headers {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 8px;
  margin-bottom: 16px;
}

.flow-col-header {
  text-align: center;
  font-size: 12px;
  font-weight: 700;
  color: var(--vp-c-text-1);
  padding: 8px;
  background: var(--vp-c-bg-elv);
  border: 1px solid var(--vp-c-border);
  border-radius: 8px;
}

.flow-steps {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.flow-step {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 12px;
  background: var(--vp-c-bg-elv);
  border: 1px solid var(--vp-c-border);
  border-radius: 8px;
}

.step-indicator {
  flex-shrink: 0;
}

.step-num {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 22px;
  height: 22px;
  border-radius: 11px;
  background: var(--vp-c-brand-soft);
  color: var(--vp-c-text-1);
  font-size: 11px;
  font-weight: 700;
}

.step-content {
  flex: 1;
  min-width: 0;
}

.step-action {
  font-size: 13px;
  font-weight: 600;
  color: var(--vp-c-text-1);
}

.step-detail {
  font-size: 11px;
  color: var(--vp-c-text-3);
  margin-top: 1px;
}

.step-direction {
  flex-shrink: 0;
}

.dir-badge {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 24px;
  height: 24px;
  border-radius: 6px;
  font-size: 14px;
  font-weight: 500;
}

.dir-badge.right {
  background: #DBEAFE;
  color: #1D4ED8;
}

.dir-badge.left {
  background: #DCFCE7;
  color: #166534;
}

.dir-badge.self {
  background: var(--vp-c-brand-soft);
  color: var(--vp-c-text-2);
}

/* Dark mode */
.dark .dir-badge.right { background: #1E3A5F; color: #93C5FD; }
.dark .dir-badge.left { background: #14532D; color: #86EFAC; }

/* Mobile */
@media (max-width: 768px) {
  .arch-diagram { padding: 16px 12px; }
  .flow-headers { display: none; }
  .step-action { font-size: 12px; }
}
</style>
