import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { C, fontFamily } from "../theme";
import { Backdrop } from "./Backdrop";

const ITEMS: [string, string][] = [
  ["Claude Code", "#d97757"],
  ["Codex", "#e8e8e8"],
  ["Gemini CLI", "#2a73f5"],
  ["Qwen Code", "#615ced"],
  ["Cursor", "#e8e8e8"],
  ["opencode", "#e8e8e8"],
  ["Antigravity", "#0f9d8a"],
];

/** The breadth beat: "EVERY AGENT." with the provider pills staggering in. */
export const Providers: React.FC = () => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill>
      <Backdrop />
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", flexDirection: "column", gap: 48 }}>
        <div
          style={{
            fontFamily,
            fontWeight: 700,
            fontSize: 140,
            letterSpacing: "-0.045em",
            color: C.ink,
            opacity: interpolate(frame, [0, 6], [0, 1], { extrapolateRight: "clamp" }),
          }}
        >
          EVERY <span style={{ color: C.blue }}>AGENT.</span>
        </div>
        <div style={{ display: "flex", flexWrap: "wrap", gap: 16, maxWidth: 1320, justifyContent: "center" }}>
          {ITEMS.map(([name, dot], i) => {
            const op = interpolate(frame, [8 + i * 3, 16 + i * 3], [0, 1], {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
            });
            return (
              <div
                key={name}
                style={{
                  opacity: op,
                  transform: `translateY(${interpolate(op, [0, 1], [16, 0])}px)`,
                  display: "flex",
                  alignItems: "center",
                  gap: 12,
                  border: `1px solid ${C.hair}`,
                  borderRadius: 999,
                  padding: "14px 26px",
                  background: "rgba(255,255,255,.02)",
                }}
              >
                <span style={{ width: 14, height: 14, borderRadius: "50%", background: dot }} />
                <span style={{ fontFamily, fontSize: 40, fontWeight: 600, color: C.ink }}>{name}</span>
              </div>
            );
          })}
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
