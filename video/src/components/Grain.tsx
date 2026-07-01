import { AbsoluteFill } from "remotion";

// Film grain overlay — the website's .grain layer (screen-blended for dark).
const NOISE =
  "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.85' numOctaves='2' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E\")";

export const Grain: React.FC = () => (
  <AbsoluteFill
    style={{
      backgroundImage: NOISE,
      backgroundSize: "260px 260px",
      opacity: 0.05,
      mixBlendMode: "screen",
      pointerEvents: "none",
    }}
  />
);
