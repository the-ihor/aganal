# AGANAL hero video

The landing's hero film (`docs/assets/hero.mp4`), built in
[Remotion](https://remotion.dev) — real app screenshots interleaved with
kinetic type, a provider row, and a typing CLI terminal.

## Pipeline

```bash
npm install
npm run render          # → out/hero.mp4  (1920×1080, ~26s, silent, no captions)
```

The rendered clip is **silent and caption-free** on purpose. The voiceover,
music, and subtitles are added afterwards in **ElevenLabs**, then the result is
web-optimized and dropped into the site:

```bash
# after exporting from ElevenLabs (e.g. ~/Downloads/ElevenLabs_aganal-hero.mp4):
ffmpeg -y -i ElevenLabs_aganal-hero.mp4 \
  -c:v libx264 -crf 28 -preset veryslow -pix_fmt yuv420p -movflags +faststart \
  -c:a aac -b:a 128k ../docs/assets/hero.mp4
ffmpeg -y -ss 5.4 -i ElevenLabs_aganal-hero.mp4 -frames:v 1 -q:v 4 ../docs/assets/hero-poster.jpg
```

## Layout

- `src/Hero.tsx` — the scene list (seconds → scene). Edit here to retime cuts.
- `src/components/` — `Word` (kinetic type), `Shot` (screenshot + Ken-Burns),
  `Terminal` (typing CLI), `Providers`, `Intro`, `EndCard`, `Backdrop`, `Grain`.
- `public/shots/` — the real screenshots (copied from `docs/assets/shots/`).

`npm run dev` opens the Remotion studio for scrubbing/previewing.
