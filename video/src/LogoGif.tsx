import { AbsoluteFill, useCurrentFrame, useVideoConfig } from "remotion";
import { fontFamily } from "./theme";

// AGANAL logo lockup: the magnifier mark over the wordmark, with the agent
// (a robot) as a faint watermark in the background. Seamless loop; flat colours.

const BASE = 742;
const BARS = [
  { x: 210.4, w: 56.8, h: 177.6 },
  { x: 295.6, w: 56.8, h: 266.3 },
  { x: 380.8, w: 56.8, h: 213.1 },
  { x: 466.0, w: 56.8, h: 355.1 },
  { x: 551.3, w: 56.8, h: 266.3 },
];
const SLATE = "#c9ccd9";
const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

/** The agent — used faint, in the background. */
const Robot: React.FC = () => (
  <svg width="100%" height="100%" viewBox="0 0 236 232">
    <line x1="118" y1="72" x2="118" y2="38" stroke={SLATE} strokeWidth="10" strokeLinecap="round" />
    <circle cx="118" cy="26" r="13" fill="#9aa4ff" />
    <rect x="10" y="116" width="18" height="48" rx="9" fill={SLATE} />
    <rect x="208" y="116" width="18" height="48" rx="9" fill={SLATE} />
    <rect x="26" y="72" width="184" height="150" rx="34" fill={SLATE} />
    <rect x="50" y="96" width="136" height="102" rx="20" fill="#20222c" />
    <circle cx="88" cy="140" r="15" fill="#9aa4ff" />
    <circle cx="148" cy="140" r="15" fill="#9aa4ff" />
    <path d="M92 172 Q118 188 144 172" stroke="#8b90a2" strokeWidth="7" fill="none" strokeLinecap="round" />
  </svg>
);

/** Magnifier + chart. The lens hovers gently and stays over the bars. */
const Mark: React.FC = () => {
  const frame = useCurrentFrame();
  const { durationInFrames: D } = useVideoConfig();
  const t = frame / D;
  const dx = 20 * Math.sin(2 * Math.PI * t);       // gentle hover, stays on the chart
  const dy = 9 * Math.sin(2 * Math.PI * 2 * t);
  const pulse = 0.5 + 0.5 * Math.sin(2 * Math.PI * 2 * t);
  const blue = `rgb(${Math.round(lerp(91, 150, pulse))},${Math.round(lerp(108, 160, pulse))},${Math.round(lerp(240, 255, pulse))})`;
  const glow = 0.22 + 0.32 * pulse;
  const blueH = 222 * (0.94 + 0.06 * pulse);
  const blueY = 520.1 - blueH;

  return (
    <svg width="100%" height="100%" viewBox="80 195 860 580">
      <defs>
        <clipPath id="glass"><circle cx="567.2" cy="413.5" r="131.4" /></clipPath>
        <filter id="soft" x="-60%" y="-60%" width="220%" height="220%"><feGaussianBlur stdDeviation="20" /></filter>
      </defs>
      {BARS.map((b, i) => (
        <rect key={i} x={b.x} y={BASE - b.h} width={b.w} height={b.h} rx="13" fill={SLATE} />
      ))}
      <rect x="203.2" y="731.4" width="424.4" height="21.3" rx="10.6" fill="#eef0f6" />
      <g transform={`translate(${dx}, ${dy})`}>
        <g clipPath="url(#glass)">
          <circle cx="567.2" cy="413.5" r="131.4" fill="#2a2d3a" />
          <rect x="551.3" y={blueY} width="88.8" height={blueH} rx="21" fill={blue} opacity={glow} filter="url(#soft)" />
          <rect x="490.9" y="386.9" width="46.2" height="133.2" rx="11" fill={SLATE} />
          <rect x="551.3" y={blueY} width="88.8" height={blueH} rx="21" fill={blue} />
        </g>
        <circle cx="567.2" cy="413.5" r="152.7" fill="none" stroke="#eef0f6" strokeWidth="42.6" />
        <line x1="679.1" y1="546.7" x2="769.3" y2="654.3" stroke="#eef0f6" strokeWidth="49.7" strokeLinecap="round" />
      </g>
    </svg>
  );
};

export const LogoGif: React.FC = () => {
  const frame = useCurrentFrame();
  const { durationInFrames: D } = useVideoConfig();
  const t = frame / D;

  // AGANAL wordmark with a soft sheen sweeping across (period-locked → loops).
  const p = 760;
  const aganal: React.CSSProperties = {
    fontFamily,
    fontWeight: 700,
    fontSize: 74,
    letterSpacing: "-0.045em",
    lineHeight: 1,
    backgroundImage: `repeating-linear-gradient(100deg, #ccd0dd 0px, #ccd0dd ${p * 0.42}px, #ffffff ${p * 0.5}px, #ccd0dd ${p * 0.58}px, #ccd0dd ${p}px)`,
    backgroundPosition: `${-t * p}px 0`,
    WebkitBackgroundClip: "text",
    backgroundClip: "text",
    color: "transparent",
  };

  return (
    <AbsoluteFill style={{ background: "#14151c" }}>
      {/* agent — faint background watermark */}
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
        <div style={{ width: 360, height: 354, opacity: 0.08 }}><Robot /></div>
      </AbsoluteFill>

      {/* foreground lockup */}
      <AbsoluteFill style={{ flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 4 }}>
        <div style={{ width: 372, height: 251 }}><Mark /></div>
        <div style={aganal}>AGANAL</div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
