import { AbsoluteFill, Img, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { C, fontFamily, mono } from "../theme";
import { Backdrop } from "./Backdrop";

/** Closing lockup: icon, wordmark, one-liner, and the URL. */
export const EndCard: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const s = spring({ frame, fps, config: { damping: 14, stiffness: 120 } });
  const op = interpolate(frame, [0, 8], [0, 1], { extrapolateRight: "clamp" });
  return (
    <AbsoluteFill>
      <Backdrop />
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", flexDirection: "column", gap: 22, opacity: op }}>
        <Img
          src={staticFile("icon.png")}
          style={{
            width: 190,
            height: 190,
            transform: `scale(${interpolate(s, [0, 1], [0.8, 1])})`,
            filter: "drop-shadow(0 30px 60px rgba(0,0,0,.6))",
          }}
        />
        <div style={{ fontFamily, fontWeight: 700, fontSize: 124, letterSpacing: "-0.04em", color: C.ink }}>AGANAL</div>
        <div style={{ fontFamily, fontSize: 36, color: C.inkSoft }}>See what your agents actually did.</div>
        <div style={{ fontFamily: mono, fontSize: 25, color: C.dim, marginTop: 10 }}>free · open source · macOS 14+</div>
        <div style={{ fontFamily: mono, fontSize: 28, color: C.blueLo }}>aganal.the-ihor.com</div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
