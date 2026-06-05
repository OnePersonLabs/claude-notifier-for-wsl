#!/usr/bin/env bash
# claude-super-notifier installer (WSL -> Windows).
#
# Installs a Claude Code hook that plays a wav + speaks a short line via Windows
# SAPI text-to-speech when Claude finishes, asks a question, or needs input.
# Audio goes out through Windows (powershell.exe interop), so it needs no WSL
# audio stack -- just a working Windows default playback device.
#
# Run from inside WSL:  ./install.sh
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
HOOKS_DIR="${CLAUDE_DIR}/hooks"
SETTINGS="${CLAUDE_DIR}/settings.json"

command -v powershell.exe >/dev/null 2>&1 || { echo "ERROR: powershell.exe not found -- run this inside WSL."; exit 1; }
command -v wslpath        >/dev/null 2>&1 || { echo "ERROR: wslpath not found -- run this inside WSL."; exit 1; }
command -v node           >/dev/null 2>&1 || { echo "ERROR: node not found on PATH."; exit 1; }

# Resolve the Windows user profile (e.g. C:\Users\alice) and derive sound dirs.
WINPROFILE="$(powershell.exe -NoProfile -Command '$env:USERPROFILE' | tr -d '\r')"
[ -n "$WINPROFILE" ] || { echo "ERROR: could not resolve Windows USERPROFILE."; exit 1; }
WIN_SOUND_DIR="${WINPROFILE}\\.claude\\sounds"          # Windows form, single backslashes
WSL_SOUND_DIR="$(wslpath "$WINPROFILE")/.claude/sounds" # /mnt/c/Users/<user>/.claude/sounds

echo "Windows profile : ${WINPROFILE}"
echo "Sound dir (win) : ${WIN_SOUND_DIR}"
echo "Sound dir (wsl) : ${WSL_SOUND_DIR}"

# 1. Sounds -> Windows-native dir (SoundPlayer needs a real Windows path).
mkdir -p "$WSL_SOUND_DIR"
cp "$SRC"/sounds/*.wav "$WSL_SOUND_DIR"/

# 2. Hook script -> ~/.claude/hooks
mkdir -p "$HOOKS_DIR"
cp "$SRC/hooks/claude-sound.js" "$HOOKS_DIR/claude-sound.js"

# 3. Per-machine config (the hook reads winSoundDir from here) + settings wiring.
WIN_SOUND_DIR="$WIN_SOUND_DIR" HOOKS_DIR="$HOOKS_DIR" SETTINGS="$SETTINGS" node <<'NODE'
const fs = require("fs");
const path = require("path");
const { HOOKS_DIR, SETTINGS, WIN_SOUND_DIR } = process.env;

// config next to the hook
fs.writeFileSync(
  path.join(HOOKS_DIR, "claude-sound.config.json"),
  JSON.stringify({ winSoundDir: WIN_SOUND_DIR }, null, 2) + "\n"
);

// register hooks (idempotent)
const SCRIPT = path.join(HOOKS_DIR, "claude-sound.js");
const cmd = (m) => `node "${SCRIPT}" ${m}`;
let s = {};
try { s = JSON.parse(fs.readFileSync(SETTINGS, "utf8")); } catch {}
s.hooks = s.hooks || {};
const has = (arr, m) => (arr || []).some((e) => (e.hooks || []).some((h) => h.command === cmd(m)));

s.hooks.Stop = s.hooks.Stop || [];
if (!has(s.hooks.Stop, "stop")) s.hooks.Stop.push({ hooks: [{ type: "command", command: cmd("stop") }] });

s.hooks.PreToolUse = s.hooks.PreToolUse || [];
if (!has(s.hooks.PreToolUse, "question"))
  s.hooks.PreToolUse.push({ matcher: "AskUserQuestion", hooks: [{ type: "command", command: cmd("question") }] });

s.hooks.PermissionRequest = s.hooks.PermissionRequest || [];
if (!has(s.hooks.PermissionRequest, "permission"))
  s.hooks.PermissionRequest.push({ hooks: [{ type: "command", command: cmd("permission") }] });

fs.writeFileSync(SETTINGS, JSON.stringify(s, null, 2) + "\n");
console.log("Wired Stop / PreToolUse(AskUserQuestion) / PermissionRequest -> claude-sound.js");
NODE

echo
echo "Done. Restart Claude Code (or start a new session) to load the hooks."
echo "Test now:  echo '{}' | node \"${HOOKS_DIR}/claude-sound.js\" stop"
