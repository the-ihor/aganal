import { loadFont as loadDisplay } from "@remotion/google-fonts/SpaceGrotesk";
import { loadFont as loadMono } from "@remotion/google-fonts/JetBrainsMono";

// Same fonts as the website.
export const { fontFamily } = loadDisplay();
export const { fontFamily: mono } = loadMono();

// Dark analytics palette — mirrors docs/index.html :root tokens.
export const C = {
  bg: "#0a0b0f",
  panel: "#11131a",
  panel2: "#0d0f15",
  hair: "rgba(255,255,255,.10)",
  ink: "#eef0f6",
  inkSoft: "#c3c7d4",
  dim: "#8b90a2",
  faint: "#5c6172",
  blue: "#6d7bff",
  blueDeep: "#4c5ced",
  blueLo: "#9aa4ff",
  pos: "#41d69c",
} as const;

export const FPS = 30;
/** Seconds → frame (snapped). */
export const f = (sec: number) => Math.round(sec * FPS);
