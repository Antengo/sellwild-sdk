import { Composition } from 'remotion'
import { SellwildPitch } from './Pitch'

export const RemotionRoot = () => {
  return (
    <Composition
      id="SellwildPitch"
      component={SellwildPitch}
      durationInFrames={30 * 75}
      fps={30}
      width={1920}
      height={1080}
    />
  )
}
