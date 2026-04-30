import DefaultTheme from 'vitepress/theme'
import ArchitectureDiagram from './components/ArchitectureDiagram.vue'
import SystemOverviewDiagram from './components/SystemOverviewDiagram.vue'
import RequestFlowDiagram from './components/RequestFlowDiagram.vue'
import AuctionFlowDiagram from './components/AuctionFlowDiagram.vue'
import PrivacyFlowDiagram from './components/PrivacyFlowDiagram.vue'
import './custom.css'

export default {
  extends: DefaultTheme,
  enhanceApp({ app }) {
    app.component('ArchitectureDiagram', ArchitectureDiagram)
    app.component('SystemOverviewDiagram', SystemOverviewDiagram)
    app.component('RequestFlowDiagram', RequestFlowDiagram)
    app.component('AuctionFlowDiagram', AuctionFlowDiagram)
    app.component('PrivacyFlowDiagram', PrivacyFlowDiagram)
  },
}
