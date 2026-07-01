import { AbsoluteFill } from "remotion";
import { C } from "../theme";

const GRID = "rgba(255,255,255,.035)";
const MASK = "radial-gradient(120% 75% at 50% 0%, #000 30%, transparent 80%)";

/** The site's dark canvas: graph-paper grid + a soft accent field up top. */
export const Backdrop: React.FC<{ glow?: boolean }> = ({ glow = true }) => (
  <AbsoluteFill style={{ background: C.bg }}>
    <AbsoluteFill
      style={{
        backgroundImage: `linear-gradient(${GRID} 1px, transparent 1px), linear-gradient(90deg, ${GRID} 1px, transparent 1px)`,
        backgroundSize: "60px 60px",
        opacity: 0.6,
        WebkitMaskImage: MASK,
        maskImage: MASK,
      }}
    />
    {glow ? (
      <div
        style={{
          position: "absolute",
          top: "-30%",
          left: "50%",
          transform: "translateX(-50%)",
          width: "120%",
          height: "90%",
          background: "radial-gradient(46% 60% at 60% 0%, rgba(109,123,255,.30), transparent 68%)",
          filter: "blur(70px)",
          opacity: 0.85,
        }}
      />
    ) : null}
  </AbsoluteFill>
);
