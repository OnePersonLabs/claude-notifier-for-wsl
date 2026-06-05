#!/usr/bin/env bash
# claude-super-notifier uninstaller. Removes the hook + config and deregisters
# it from ~/.claude/settings.json. Leaves the copied wav files in place (delete
# C:\Users\<you>\.claude\sounds yourself if you want them gone).
set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
HOOKS_DIR="${CLAUDE_DIR}/hooks"
SETTINGS="${CLAUDE_DIR}/settings.json"

rm -f "${HOOKS_DIR}/claude-sound.js" "${HOOKS_DIR}/claude-sound.config.json"

if [ -f "$SETTINGS" ]; then
  SETTINGS="$SETTINGS" node <<'NODE'
const fs = require("fs");
const { SETTINGS } = process.env;
let s;
try { s = JSON.parse(fs.readFileSync(SETTINGS, "utf8")); } catch { process.exit(0); }
const h = s.hooks || {};
const isOurs = (e) => (e.hooks || []).some((x) => (x.command || "").includes("claude-sound.js"));
for (const k of ["Stop", "PreToolUse", "PermissionRequest"]) {
  if (!h[k]) continue;
  h[k] = h[k].filter((e) => !isOurs(e));
  if (h[k].length === 0) delete h[k];
}
fs.writeFileSync(SETTINGS, JSON.stringify(s, null, 2) + "\n");
console.log("Deregistered claude-sound.js from settings.json");
NODE
fi

echo "Uninstalled. Restart Claude Code to drop the hooks."
