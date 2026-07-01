import { Composition } from "remotion";
import { Hero, HERO_SECONDS } from "./Hero";
import { FPS, f } from "./theme";

export const RemotionRoot: React.FC = () => (
  <Composition
    id="Hero"
    component={Hero}
    durationInFrames={f(HERO_SECONDS)}
    fps={FPS}
    width={1920}
    height={1080}
  />
);
