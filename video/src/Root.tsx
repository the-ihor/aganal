import { Composition } from "remotion";
import { Hero, HERO_SECONDS } from "./Hero";
import { LogoGif } from "./LogoGif";
import { FPS, f } from "./theme";

export const RemotionRoot: React.FC = () => (
  <>
    <Composition
      id="Hero"
      component={Hero}
      durationInFrames={f(HERO_SECONDS)}
      fps={FPS}
      width={1920}
      height={1080}
    />
    <Composition
      id="LogoGif"
      component={LogoGif}
      durationInFrames={f(3.0)}
      fps={FPS}
      width={480}
      height={480}
    />
  </>
);
