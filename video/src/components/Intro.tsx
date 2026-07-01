import { AbsoluteFill, Img, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { C, fontFamily } from "../theme";
import { Backdrop } from "./Backdrop";

/** Opening lockup: the app icon + AGANAL wordmark settling in. */
export const Intro: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const s = spring({ frame, fps, config: { damping: 13, stiffness: 120 } });
  const op = interpolate(frame, [0, 6], [0, 1], { extrapolateRight: "clamp" });
  return (
    <AbsoluteFill>
      <Backdrop />
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", flexDirection: "row", gap: 28, opacity: op }}>
        <Img
          src={staticFile("icon.png")}
          style={{
            width: 150,
            height: 150,
            transform: `scale(${interpolate(s, [0, 1], [0.7, 1])})`,
            filter: "drop-shadow(0 26px 50px rgba(0,0,0,.6))",
          }}
        />
        <div
          style={{
            fontFamily,
            fontWeight: 700,
            fontSize: 132,
            letterSpacing: "-0.04em",
            color: C.ink,
            transform: `translateX(${interpolate(s, [0, 1], [-34, 0])}px)`,
          }}
        >
          AGANAL
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
