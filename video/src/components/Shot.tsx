import { AbsoluteFill, Img, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { Backdrop } from "./Backdrop";

/** A real app screenshot on the dark canvas: fade + scale-in, then a slow
 * Ken-Burns drift so a static capture feels alive. */
export const Shot: React.FC<{ src: string; width?: string; drift?: number; zoom?: number }> = ({
  src,
  width = "76%",
  drift = -26,
  zoom = 0.05,
}) => {
  const frame = useCurrentFrame();
  const { durationInFrames, fps } = useVideoConfig();
  const enter = spring({ frame, fps, config: { damping: 18, stiffness: 90 } });
  const p = frame / Math.max(durationInFrames - 1, 1);
  const scale = interpolate(enter, [0, 1], [0.94, 1]) * (1 + p * zoom);
  const op = interpolate(frame, [0, 9], [0, 1], { extrapolateRight: "clamp" });
  const y = interpolate(p, [0, 1], [0, drift]);
  return (
    <AbsoluteFill>
      <Backdrop />
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
        <Img
          src={staticFile(src)}
          style={{
            width,
            transform: `translateY(${y}px) scale(${scale})`,
            opacity: op,
            filter: "drop-shadow(0 50px 90px rgba(0,0,0,.62))",
          }}
        />
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
