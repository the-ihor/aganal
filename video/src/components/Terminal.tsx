import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { C, mono } from "../theme";
import { Backdrop } from "./Backdrop";

const CMD = "aganal analytics session.jsonl";
const OUT = [
  "{",
  '  "meta":    { "provider": "claude-code", "model": "claude-opus-4-8" },',
  '  "summary": { "events": 899, "toolCalls": 246,',
  '               "outputTokens": 512853, "peakContextPercent": 71 },',
  '  "toolUsage": [ { "name": "Bash", "count": 94 }, … ]',
  "}",
];

const Dot: React.FC<{ c: string }> = ({ c }) => (
  <span style={{ width: 13, height: 13, borderRadius: "50%", background: c, display: "inline-block" }} />
);

/** A terminal typing the CLI command, then the JSON streaming in — the
 * "hand a session to an agent / drive it from the CLI" beat. */
export const Terminal: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const enter = spring({ frame, fps, config: { damping: 18, stiffness: 90 } });
  const scale = interpolate(enter, [0, 1], [0.96, 1]);
  const op = interpolate(frame, [0, 8], [0, 1], { extrapolateRight: "clamp" });

  const typed = Math.max(0, Math.min(CMD.length, Math.floor((frame - 8) / 1.1)));
  const outStart = 8 + CMD.length * 1.1 + 8;
  const linesShown = Math.max(0, Math.min(OUT.length, Math.floor((frame - outStart) / 4)));
  const caret = frame % 16 < 8 ? "▋" : " ";

  return (
    <AbsoluteFill>
      <Backdrop />
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
        <div
          style={{
            width: 1240,
            transform: `scale(${scale})`,
            opacity: op,
            background: "#0b0d12",
            border: `1px solid ${C.hair}`,
            borderRadius: 18,
            overflow: "hidden",
            boxShadow: "0 50px 120px -50px rgba(0,0,0,.9)",
          }}
        >
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: 8,
              padding: "16px 20px",
              borderBottom: `1px solid ${C.hair}`,
              background: "rgba(255,255,255,.02)",
            }}
          >
            <Dot c="#ff5f57" />
            <Dot c="#febc2e" />
            <Dot c="#28c840" />
            <span style={{ marginLeft: 8, fontFamily: mono, fontSize: 21, color: C.faint }}>zsh — aganal</span>
          </div>
          <div style={{ padding: 34, fontFamily: mono, fontSize: 27, lineHeight: 1.7, minHeight: 360 }}>
            <div>
              <span style={{ color: C.faint }}>$ </span>
              <span style={{ color: C.ink }}>{CMD.slice(0, typed)}</span>
              <span style={{ color: C.blue }}>{typed >= CMD.length ? "" : caret}</span>
            </div>
            {OUT.slice(0, linesShown).map((line, i) => (
              <div key={i} style={{ color: /\d{3,}/.test(line) ? C.blueLo : C.inkSoft, whiteSpace: "pre" }}>
                {line}
              </div>
            ))}
          </div>
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
