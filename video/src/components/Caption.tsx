import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { C, fontFamily } from "../theme";

/** A pill caption over a screenshot — near the top or bottom edge. */
export const Caption: React.FC<{ children: React.ReactNode; top?: boolean }> = ({ children, top }) => {
  const frame = useCurrentFrame();
  const op = interpolate(frame, [0, 8], [0, 1], { extrapolateRight: "clamp" });
  const y = interpolate(frame, [0, 12], [top ? -16 : 16, 0], { extrapolateRight: "clamp" });
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: top ? "flex-start" : "flex-end", padding: 66 }}>
      <div
        style={{
          transform: `translateY(${y}px)`,
          opacity: op,
          background: "rgba(17,19,26,.82)",
          border: `1px solid ${C.hair}`,
          backdropFilter: "blur(6px)",
          WebkitBackdropFilter: "blur(6px)",
          color: C.ink,
          fontFamily,
          fontSize: 38,
          fontWeight: 600,
          letterSpacing: "-0.02em",
          padding: "14px 30px",
          borderRadius: 14,
          boxShadow: "0 26px 60px -30px rgba(0,0,0,.85)",
        }}
      >
        {children}
      </div>
    </AbsoluteFill>
  );
};
