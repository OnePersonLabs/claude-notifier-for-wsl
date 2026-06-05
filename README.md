# claude-notifier-for-wsl

A dead-simple Claude Code notifier for **WSL → Windows**: plays a wav and then
**speaks** a short line via Windows text-to-speech when Claude finishes a task,
asks you a question, or needs input.

The spoken line is the point -- "task complete" or the actual question read
aloud is far harder to tune out than a ding you stop hearing after a day.

## How it works

A single hook script (`hooks/claude-sound.js`) runs in WSL and hands playback to
`powershell.exe` over interop:

```
(New-Object Media.SoundPlayer '<wav>').PlaySync(); (New-Object -ComObject SAPI.SpVoice).Speak('<text>')
```

Windows plays the audio as the logged-in user, so **no WSL/PulseAudio/WSLg audio
stack is required** -- you just need a working Windows default playback device.
It's also unaffected by muting Windows _system event sounds_ (that only silences
system events, not wav/TTS playback).

| Claude event                     | wav                 | spoken                                    |
| -------------------------------- | ------------------- | ----------------------------------------- |
| `Stop` (task done)               | `task-complete.wav` | "task complete"                           |
| `Stop` (last msg is a question)  | `question.wav`      | the trailing question clause              |
| `PreToolUse` / `AskUserQuestion` | `question.wav`      | the question text (from the hook payload) |
| `PermissionRequest`              | `needs-input.wav`   | "needs input"                             |

Playback is non-blocking (detached `powershell.exe`), so hooks never stall the CLI.

## Install

From inside WSL:

```bash
./install.sh
```

It auto-detects your Windows user, copies the wavs to
`C:\Users\<you>\.claude\sounds`, drops `claude-sound.js` +
`claude-sound.config.json` into `~/.claude/hooks/`, and registers the three
hooks in `~/.claude/settings.json` (idempotent -- safe to re-run). Restart Claude
Code afterward.

Quick test without restarting:

```bash
echo '{}' | node ~/.claude/hooks/claude-sound.js stop        # task-complete + "task complete"
node ~/.claude/hooks/claude-sound.js permission < /dev/null  # needs-input + "needs input"
```

## Uninstall

```bash
./uninstall.sh
```

Removes the hook + config and deregisters it from `settings.json`. (Leaves the
copied wavs under `C:\Users\<you>\.claude\sounds`.)

## Config

`~/.claude/hooks/claude-sound.config.json` holds the one machine-specific value:

```json
{ "winSoundDir": "C:\\Users\\<you>\\.claude\\sounds" }
```

`install.sh` writes it for you. Swap in your own wavs (keep the three filenames)
or change the spoken strings directly in `claude-sound.js`.

## Requirements

- WSL with `powershell.exe` interop (default on WSL2) and `wslpath`
- `node` on PATH inside WSL
- A Windows default playback device you can actually hear (yes, check the cable)

## Note on the bundled sounds

The three wavs were borrowed from the original [claude-notifier](https://github.com/ashmitb95/claude-notifier) project.
