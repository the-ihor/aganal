import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { C, fontFamily } from "../theme";
import { Backdrop } from "./Backdrop";

/** Full-bleed kinetic word that punches in: reveal from below + scale overshoot. */
export const Word: React.FC<{ children: React.ReactNode; size?: number; sub?: string; glow?: boolean }> = ({
  children,
  size = 210,
  sub,
  glow = true,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const enter = spring({ frame, fps, config: { damping: 14, stiffness: 130, mass: 0.7 } });
  const y = interpolate(enter, [0, 1], [120, 0]);
  const scale = interpolate(enter, [0, 1], [1.1, 1]);
  const op = interpolate(frame, [0, 4], [0, 1], { extrapolateRight: "clamp" });

  return (
    <AbsoluteFill>
      <Backdrop glow={glow} />
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", flexDirection: "column", gap: 30 }}>
        <div style={{ overflow: "hidden", padding: "0.14em 0.06em" }}>
          <div
            style={{
              fontFamily,
              fontWeight: 700,
              letterSpacing: "-0.045em",
              fontSize: size,
              lineHeight: 0.86,
              color: C.ink,
              whiteSpace: "nowrap",
              textAlign: "center",
              transform: `translateY(${y}px) scale(${scale})`,
              opacity: op,
            }}
          >
            {children}
          </div>
        </div>
        {sub ? (
          <div
            style={{
              fontFamily,
              fontSize: 32,
              fontWeight: 500,
              letterSpacing: "0.02em",
              color: C.dim,
              opacity: interpolate(frame, [6, 16], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" }),
            }}
          >
            {sub}
          </div>
        ) : null}
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
