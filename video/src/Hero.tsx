import { AbsoluteFill, Series } from "remotion";
import { C, f } from "./theme";
import { Grain } from "./components/Grain";
import { Intro } from "./components/Intro";
import { Word } from "./components/Word";
import { Shot } from "./components/Shot";
import { Terminal } from "./components/Terminal";
import { Providers } from "./components/Providers";
import { EndCard } from "./components/EndCard";

// [seconds, scene] — real screenshots interleaved with kinetic type + the CLI.
// No captions: the narration carries the explanation.
const scenes: [number, React.ReactNode][] = [
  [1.4, <Intro />],
  [1.0, <Word size={230}>STOP GUESSING.</Word>],
  [1.5, <Word size={200}>START <span style={{ color: C.blue }}>ANALYZING.</span></Word>],
  [3.0, <Shot src="shots/analysis.webp" />],
  [1.6, <Word size={230} sub="tokens · tool calls · context · retries">MEASURED.</Word>],
  [2.6, <Shot src="shots/events.webp" />],
  [2.2, <Shot src="shots/raw-jsonl.webp" />],
  [2.6, <Providers />],
  [3.9, <Terminal />],
  [2.9, <Shot src="shots/agent.webp" />],
  [3.4, <EndCard />],
];

export const HERO_SECONDS = scenes.reduce((a, [d]) => a + d, 0);

export const Hero: React.FC = () => (
  <AbsoluteFill style={{ background: C.bg }}>
    <Series>
      {scenes.map(([dur, node], i) => (
        <Series.Sequence key={i} durationInFrames={f(dur)}>
          {node}
        </Series.Sequence>
      ))}
    </Series>
    <Grain />
  </AbsoluteFill>
);
