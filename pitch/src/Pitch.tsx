import { TransitionSeries, linearTiming } from '@remotion/transitions'
import { fade } from '@remotion/transitions/fade'
import { slide } from '@remotion/transitions/slide'
import { TitleSlide } from './components/TitleSlide'
import { DemoListingsSlide } from './components/DemoListingsSlide'
import { DemoAuctionSlide } from './components/DemoAuctionSlide'
import { DashboardSlide } from './components/DashboardSlide'
import { DocsSlide } from './components/DocsSlide'
import { ArchitectureSlide } from './components/ArchitectureSlide'
import { SSPSlide } from './components/SSPSlide'
import { ComparisonSlide } from './components/ComparisonSlide'
import { RevenueSlide } from './components/RevenueSlide'
import { PilotSlide } from './components/PilotSlide'
import { ClosingSlide } from './components/ClosingSlide'

const SLIDE = 7 * 30   // 7 seconds per slide
const TITLE = 4 * 30   // 4 seconds for title — just flash it
const TRANS = 12

export const SellwildPitch = () => {
  return (
    <TransitionSeries>
      {/* 1. Title — quick, 4 seconds */}
      <TransitionSeries.Sequence durationInFrames={TITLE}>
        <TitleSlide />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition presentation={fade()} timing={linearTiming({ durationInFrames: TRANS })} />

      {/* 2. Demo — Listings + Real Ads (THE MONEY SHOT) */}
      <TransitionSeries.Sequence durationInFrames={SLIDE}>
        <DemoListingsSlide />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition presentation={slide({ direction: 'from-right' })} timing={linearTiming({ durationInFrames: TRANS })} />

      {/* 3. Demo — Auction Transparency */}
      <TransitionSeries.Sequence durationInFrames={SLIDE}>
        <DemoAuctionSlide />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition presentation={fade()} timing={linearTiming({ durationInFrames: TRANS })} />

      {/* 4. Admin Dashboard */}
      <TransitionSeries.Sequence durationInFrames={SLIDE}>
        <DashboardSlide />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition presentation={slide({ direction: 'from-right' })} timing={linearTiming({ durationInFrames: TRANS })} />

      {/* 5. Docs Site */}
      <TransitionSeries.Sequence durationInFrames={SLIDE}>
        <DocsSlide />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition presentation={slide({ direction: 'from-right' })} timing={linearTiming({ durationInFrames: TRANS })} />

      {/* 6. Architecture — how it works */}
      <TransitionSeries.Sequence durationInFrames={SLIDE}>
        <ArchitectureSlide />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition presentation={fade()} timing={linearTiming({ durationInFrames: TRANS })} />

      {/* 6. SSP Partners */}
      <TransitionSeries.Sequence durationInFrames={SLIDE}>
        <SSPSlide />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition presentation={fade()} timing={linearTiming({ durationInFrames: TRANS })} />

      {/* 7. Comparison — why us */}
      <TransitionSeries.Sequence durationInFrames={SLIDE}>
        <ComparisonSlide />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition presentation={fade()} timing={linearTiming({ durationInFrames: TRANS })} />

      {/* 8. Pilot — zero risk */}
      <TransitionSeries.Sequence durationInFrames={SLIDE}>
        <PilotSlide />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition presentation={fade()} timing={linearTiming({ durationInFrames: TRANS })} />

      {/* 10. Closing */}
      <TransitionSeries.Sequence durationInFrames={SLIDE}>
        <ClosingSlide />
      </TransitionSeries.Sequence>
    </TransitionSeries>
  )
}
