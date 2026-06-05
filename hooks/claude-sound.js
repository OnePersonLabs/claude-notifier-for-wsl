#!/usr/bin/env node
// Claude Code sound + speech hook (WSL -> Windows).
//
// Plays a wav and then speaks a short line via Windows' SAPI text-to-speech,
// handed to powershell.exe over WSL interop. This deliberately does NOT use
// WSL/PulseAudio audio -- Windows plays as the logged-in user, so it needs no
// WSLg sound setup. It is also unaffected by the Windows "system event sounds"
// profile (that only silences system *event* sounds, not wav/TTS playback).
//
// Speech is the ADHD-penetrating part: a spoken "task complete" or the actual
// question text is much harder to tune out than a ding.
//
// Usage (one script, mode by argv): claude-sound.js stop|question|permission
//   stop       -> Stop hook. task-complete.wav + "task complete", OR
//                 question.wav + the spoken question if my last message was one.
//   question   -> PreToolUse/AskUserQuestion. question.wav + the question text
//                 (pulled from the hook's stdin tool_input).
//   permission -> PermissionRequest. needs-input.wav + "needs input".
//
// The hook always exits 0 and never blocks: powershell is spawned detached and
// unref'd, so wav + speech finish after this node process exits.

const fs = require("fs");
const path = require("path");
const { spawn } = require("child_process");

// Windows-native dir holding the wavs (SoundPlayer needs a real Windows path).
// Resolved per-machine by install.sh, which writes claude-sound.config.json
// next to this file. The fallback only keeps the hook from throwing if it's
// missing -- a correct install always writes the config.
let WIN_SOUND_DIR = "C:\\Users\\Public\\claude-sounds";
try {
  const cfg = JSON.parse(fs.readFileSync(path.join(__dirname, "claude-sound.config.json"), "utf8"));
  if (cfg && typeof cfg.winSoundDir === "string" && cfg.winSoundDir) WIN_SOUND_DIR = cfg.winSoundDir;
} catch {}

const SOUND = { done: "task-complete.wav", question: "question.wav", needsInput: "needs-input.wav" };

// Make text safe + bearable for a speech synth: drop markup/markdown, collapse
// whitespace, cap length so it can't drone through a paragraph.
function clean(s) {
  return String(s == null ? "" : s)
    .replace(/<[^>]*>/g, " ")
    .replace(/[`*_#>~\[\]()]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 240);
}

// PowerShell single-quoted string literal: ' -> ''.
function psq(s) {
  return String(s).replace(/'/g, "''");
}

// Play a wav (blocking) then optionally speak text, in one detached powershell.
function playAndSpeak(file, speakText) {
  const winPath = `${WIN_SOUND_DIR}\\${file}`;
  let ps = `(New-Object Media.SoundPlayer '${psq(winPath)}').PlaySync()`;
  const text = clean(speakText);
  if (text) ps += `; (New-Object -ComObject SAPI.SpVoice).Speak('${psq(text)}')`;
  try {
    const child = spawn(
      "powershell.exe",
      ["-NoProfile", "-NonInteractive", "-Command", ps],
      { detached: true, stdio: "ignore" }
    );
    child.unref();
  } catch {}
}

// From a Stop transcript, decide if the latest assistant turn is a question.
// Returns the trailing question clause (string) to speak, "" for a structured
// question with no prose, or null if it isn't a question.
function trailingQuestion(transcriptPath) {
  try {
    if (!transcriptPath || !fs.existsSync(transcriptPath)) return null;
    const lines = fs.readFileSync(transcriptPath, "utf-8").trim().split("\n").slice(-20);
    for (let i = lines.length - 1; i >= 0; i--) {
      let msg;
      try { msg = JSON.parse(lines[i]); } catch { continue; }
      if (msg.role !== "assistant" || !Array.isArray(msg.content) || !msg.content.length) continue;
      const last = msg.content[msg.content.length - 1];
      if (last.type === "tool_use" && last.name === "AskUserQuestion") return "";
      if (last.type === "text" && typeof last.text === "string" && last.text.trim().endsWith("?")) {
        const m = last.text.match(/([^.!?\n]*\?)\s*$/); // just the final question clause
        return m ? m[1] : last.text;
      }
      return null; // latest assistant turn isn't a question
    }
  } catch {}
  return null;
}

// Read the hook's stdin payload as JSON; resolve {} on any failure or timeout.
function readStdin() {
  return new Promise((resolve) => {
    let raw = "";
    process.stdin.setEncoding("utf-8");
    process.stdin.on("data", (c) => (raw += c));
    process.stdin.on("end", () => { try { resolve(JSON.parse(raw)); } catch { resolve({}); } });
    setTimeout(() => { try { resolve(JSON.parse(raw)); } catch { resolve({}); } }, 2000);
  });
}

(async () => {
  const mode = process.argv[2];

  if (mode === "question") {
    const input = await readStdin();
    const qs = input && input.tool_input && input.tool_input.questions;
    const text = Array.isArray(qs) && qs.length
      ? qs.map((q) => q && q.question).filter(Boolean).join(". ")
      : "";
    playAndSpeak(SOUND.question, text || "Claude has a question");
    process.exit(0);
  }

  if (mode === "permission") {
    playAndSpeak(SOUND.needsInput, "needs input");
    process.exit(0);
  }

  if (mode === "stop") {
    const input = await readStdin();
    if (input.stop_hook_active) process.exit(0); // avoid re-trigger loops
    const q = trailingQuestion(input.transcript_path);
    if (q !== null) playAndSpeak(SOUND.question, q || "Claude has a question");
    else playAndSpeak(SOUND.done, "task complete");
    process.exit(0);
  }

  process.exit(0);
})();
