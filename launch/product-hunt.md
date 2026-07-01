# AGANAL — Product Hunt launch kit

**Name:** AGANAL — *Agentic sessions analysis* (Ag = agents · Anal = analysis)
**Site:** https://aganal.the-ihor.com · **Source:** https://github.com/the-ihor/aganal
**Maker:** Ihor Herasymovych · **Pricing:** Free & open source

---

## Tagline (≤60 chars) — pick one
1. **See what your AI coding agents actually did** ← recommended (benefit-first)
2. Analytics for your AI coding-agent sessions
3. Turn agent session logs into analytics — on your Mac
4. Read your AI coding sessions like a dashboard

## Description (≤260 chars)
> AGANAL reads the session logs your AI coding tools already write to disk —
> Claude Code, Codex, Gemini, Cursor, opencode & more — and turns them into
> analytics: tokens, tool calls, context pressure, retries. Native macOS,
> private, free & open source.

## Topics
Developer Tools · Artificial Intelligence · Mac · Open Source (add Analytics / Productivity)

## Built with
Swift · SwiftUI (app) · Remotion + ElevenLabs (hero video)

---

## Gallery (order matters — first item is the loop shown in feed)
1. **Hero video** — the narrated tour (`docs/assets/hero.mp4`)
2. Analysis dashboard — stat tiles + tokens-over-time + context-by-category
3. Events view — filter / search / jump to errors
4. "Analyse with Agent" tab — the prompt-kind menu
5. Raw JSONL view
6. Add-directory / providers (breadth)

**Thumbnail / logo:** the app icon (`docs/assets/icon-1024.png`).

---

## Maker's first comment (post immediately at launch)

Hey Product Hunt 👋

I build my own product, and these days most of the work runs through AI coding
agents — Claude Code, Codex, Cursor — plus a pile of **custom MCP servers** I've
wired up. Which is great, until a session goes sideways and you're left
wondering: which tool ate all the context? Why did this run balloon past 600K
tokens? Is that MCP actually pulling its weight, or just poisoning every prompt?

With a lot of custom MCPs it's genuinely not trivial to see what's happening, and
reading raw JSONL logs to find out is miserable. So I built **AGANAL** — a native
macOS app that reads the session logs your agents already leave on disk and turns
them into analytics. One shared model across every provider, so the same
dashboard works whether the run came from Claude Code, Codex, or opencode.

Where it's earned its keep: **finding the MCPs and MCP functions that quietly
poison a session** — the tools that fire on every turn, dump huge results into
context, or never get used at all. Once you can see tool usage, token cost, and
context-by-category per run, it's obvious what to cut. Trim a noisy MCP (or a
couple of its functions) and the agent gets faster, cheaper, and sharper.

What's inside:
- 📊 Tokens over time, tool-call breakdowns, context-window pressure, retries
- 🔎 A filterable event stream — with the raw JSONL underneath
- 🤖 A CLI **and** an "Analyse with Agent" tab that hands any session to an LLM
  to summarize / find errors / review cost
- 🔒 100% local — it only reads files already on your disk. No account, no
  upload, no telemetry.

It's **free and open source** (Swift/SwiftUI). Fun bit: the app's own
agent-analysis feature caught a real token-counting bug *in the app* while I was
testing it 🙂

Would love your feedback — especially which signals you'd want for spotting
context bloat, and which agents to add next.

→ Free download + source: https://aganal.the-ihor.com

## X / Twitter launch post

AGANAL — see what your AI coding agents actually did.

It reads the session logs Claude Code / Codex / Cursor / Gemini already leave on
disk and turns them into analytics: tokens, tool calls, context pressure,
retries. Native macOS. Private. Free & open source.

🚀 Live on Product Hunt today → [link]

---

## Reply templates (paste as answers to common comments)

**Is it private?** — Yes. It only reads the session logs your tools already
wrote to disk; everything is computed locally. No account, no upload, no
telemetry, works offline.

**Which agents?** — Claude Code, OpenAI Codex, Gemini CLI, Qwen Code, Cursor,
opencode, and Antigravity — plus any custom folder of JSONL sessions.

**Requirements?** — macOS 14+, Apple Silicon or Intel.

**Is it really free?** — Free and open source. Clone & `swift run`, or grab the
notarized .dmg.

**How does it work?** — Each provider maps its on-disk format into a shared
Session (a flat, time-ordered list of events); every chart/metric runs against
that one shape.

**Roadmap?** — cross-session aggregates, more providers, diffing two sessions,
export. Tell me what you'd use.

---

## Pre-launch checklist / blockers
- [ ] **Download works** — the "Download for Mac" CTA points at
      `releases/latest/download/AGANAL.dmg`, which 404s until you cut a release.
      Run `scripts/make-dmg.sh` (Developer ID + notarize) → `gh release create v0.1`.
- [ ] **Custom domain live** — `aganal.the-ihor.com` DNS CNAME is still pending;
      finish it (or use `aganal.pages.dev` as the PH link).
- [ ] **Screenshot privacy** — the current gallery shots show real repo names
      (`bugbountyfucktheplatforms`) and security-audit session titles. For a
      public launch, consider clean/demo captures.
- [ ] Launch at **12:01 AM PT**; post the maker comment first thing; line up a
      few people to comment/upvote early.
- [ ] Add the PH badge/embed back to the site once the launch URL exists.
