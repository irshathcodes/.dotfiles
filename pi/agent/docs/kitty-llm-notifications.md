# Kitty LLM Notifications for Pi

This document explains the custom Pi extension that sends macOS Kitty desktop notifications when the Pi coding agent finishes an LLM run and is ready for input.

## Files

- Extension: `~/.pi/agent/extensions/kitty-llm-notify.ts`
- Documentation: `~/.pi/agent/docs/kitty-llm-notifications.md`

Pi auto-discovers global extensions from `~/.pi/agent/extensions/*.ts`, so this extension does **not** need to be listed manually in `~/.pi/agent/settings.json`.

After editing the extension, run `/reload` inside Pi to reload it.

## Goal

The notification system is intentionally scoped to this setup:

- macOS
- Kitty terminal
- Pi coding agent running interactively inside Kitty
- Project-oriented Kitty sessions/splits

The notification should:

1. Fire when Pi finishes an agent run and is waiting for the user.
2. Avoid notifying if the exact Pi Kitty window/split is already focused.
3. Show the project folder tail in the title, e.g. `px-ui · Pi ready`.
4. When clicked, focus the originating Kitty window/split, even if it is behind another split in a stack layout.
5. Stay self-contained and easy to tweak later.

## High-level design

Pi exposes lifecycle hooks through extensions. This extension subscribes to:

- `session_start`
- `session_shutdown`
- `agent_end`

The main flow is:

```text
Pi starts/reloads
  -> session_start
  -> install Kitty notification activation input handler

User asks Pi something
  -> Pi runs LLM/tools
  -> agent_end fires
  -> if no queued follow-up/steering messages
  -> if running in interactive Kitty
  -> if exact Kitty window is not focused
  -> write OSC 99 desktop notification to stdout

User clicks notification
  -> Kitty focuses originating window by OSC 99 `a=focus`
  -> Kitty sends activation report back because `a=report`
  -> extension catches activation report
  -> extension also runs `kitty @ focus-window --match id:$KITTY_WINDOW_ID`
```

## Why OSC 99 instead of `kitten notify`?

Kitty supports desktop notifications through OSC 99 escape sequences. The extension writes OSC 99 directly to `process.stdout`.

Reasons:

- It avoids spawning a process for every notification.
- It gives direct control over the protocol metadata.
- It supports Kitty-native click behavior.
- It works in the originating Kitty window/split because the notification escape code is emitted by that Pi process.

The referenced `desktop-notify-kitty` package uses `kitten notify`; this custom version uses the same Kitty notification concept, but implements the protocol inline for more control.

## Kitty protocol details used

The extension emits two OSC 99 chunks:

1. Title chunk with `d=0`
2. Body chunk with `p=body` and `d=1`

`d=0` means “notification is not complete yet”.
`d=1` means “notification is complete; display it now”.

Payloads are base64 encoded with `e=1`, so the title/body can safely contain unicode, emoji, newlines, or other text that would otherwise be unsafe inside terminal escape codes.

Important metadata:

| Key | Value | Purpose |
| --- | --- | --- |
| `i` | generated notification id | Lets us recognize activation/close reports for notifications we sent. |
| `a` | `focus,report` | On click, Kitty focuses the originating window and reports activation back to Pi. |
| `o` | `unfocused` | Kitty should only honor the notification when the originating window is unfocused. Test notifications use `always`. |
| `f` | base64 `pi-coding-agent` | Application name for filtering. |
| `t` | base64 `llm-ready` | Notification type/category. |
| `n` | base64 `utilities-terminal` | Icon name. |
| `u` | `1` | Normal urgency. |
| `w` | `10000` | Auto-close after 10 seconds. |
| `e` | `1` | Payload is base64 encoded UTF-8. |

## Focus behavior

There are two layers of focus handling.

### 1. Skip notification if current Pi split is focused

Before sending a notification, the extension tries:

```bash
kitty @ ls --self
```

It parses Kitty’s JSON and finds the current window using either:

- `is_self: true`, or
- `id === Number($KITTY_WINDOW_ID)`

Then it checks all three levels:

- OS window focused/active
- Tab focused/active
- Kitty window/split focused/active

If all are focused, no notification is sent.

If this check fails for any reason, the extension still sends the notification with Kitty’s own `o=unfocused` metadata, so Kitty should suppress it if the originating window is focused.

### 2. Bring back the right split/session when clicked

OSC 99 with `a=focus` tells Kitty to focus the window that emitted the notification.

The extension also requests `a=report`, so when the notification is clicked Kitty sends an activation sequence back to the terminal:

```text
OSC 99 ; i=<notification-id> ; ST
```

The extension listens for raw terminal input via:

```ts
ctx.ui.onTerminalInput(...)
```

When it sees an activation report for one of its own notification ids, it runs this extra focus command:

```bash
kitty @ focus-window --match id:$KITTY_WINDOW_ID --no-response
```

This is a fallback/extra guard for your Kitty session setup, especially when the Pi split is behind another split in a stack layout.

## Project title behavior

The title is built from `ctx.cwd`:

```ts
basename(resolve(ctx.cwd))
```

Examples:

| `ctx.cwd` | Notification title |
| --- | --- |
| `/Users/irshath/work/px-ui` | `px-ui · Pi ready` |
| `/Users/irshath/.dotfiles` | `.dotfiles · Pi ready` |
| `/Users/irshath/work/frontend` | `frontend · Pi ready` |

This intentionally uses only the tail folder name, not the full path.

## Notification body behavior

The body is a compact version of the last assistant message from the completed agent run.

The extension:

- walks backward through `event.messages`
- finds the last assistant message
- extracts only text content blocks
- ignores thinking/reasoning/tool/image blocks
- strips ANSI escape codes
- replaces fenced code blocks with `[code omitted]`
- removes markdown link URLs while keeping link text
- collapses whitespace
- truncates to `MAX_BODY_CHARS` characters

Current limit:

```ts
const MAX_BODY_CHARS = 220;
```

Fallback body:

```text
Pi is ready for input.
```

## Commands

### `/kitty-notify-test`

Sends a forced test notification from the current Pi window.

Unlike normal notifications, the test notification uses:

```ts
o=always
```

So it appears even if the current Kitty window is focused.

Use this after edits:

```text
/reload
/kitty-notify-test
```

## Important constants to tweak

In `~/.pi/agent/extensions/kitty-llm-notify.ts`:

```ts
const EXPIRE_AFTER_MS = 10_000;
const MAX_BODY_CHARS = 220;
```

Common tweaks:

### Make notifications stay longer

```ts
const EXPIRE_AFTER_MS = 30_000;
```

### Make body shorter

```ts
const MAX_BODY_CHARS = 120;
```

### Change title format

Find:

```ts
const title = `${project} · Pi ready`;
```

Example alternatives:

```ts
const title = `Pi ready · ${project}`;
const title = `${project}`;
const title = `${project} needs attention`;
```

### Change fallback body

Find:

```ts
return "Pi is ready for input.";
```

### Change icon/app/type

These are base64 encoded because Kitty requires some metadata values to be base64:

```ts
const APP_NAME_BASE64 = "cGktY29kaW5nLWFnZW50"; // pi-coding-agent
const NOTIFICATION_TYPE_BASE64 = "bGxtLXJlYWR5"; // llm-ready
const ICON_NAME_BASE64 = "dXRpbGl0aWVzLXRlcm1pbmFs"; // utilities-terminal
```

To encode a new value:

```bash
printf 'new-value' | base64
```

## Why `activeNotificationIds` exists

The extension only wants to consume Kitty activation/close reports for notifications it created.

It stores generated ids in:

```ts
const activeNotificationIds = new Set<string>();
```

When terminal input arrives, the extension parses OSC 99 reports. If the id is known, it handles and removes the sequence from user input. If the id is unknown, it leaves the input untouched.

Ids are cleaned up after:

```ts
EXPIRE_AFTER_MS + 60_000
```

This prevents stale ids from living forever.

## Shutdown/reload cleanup

On `session_shutdown`, the extension:

- removes the terminal input handler
- clears cleanup timers
- clears active notification ids

This matters because `/reload`, `/new`, `/resume`, `/fork`, and quitting Pi all tear down extension runtime state.

## Known assumptions

This extension assumes:

- Pi is running interactively, not `-p`/print mode.
- `process.stdout` is a TTY.
- `KITTY_WINDOW_ID` exists.
- Kitty remote control is available for the fallback focus command.
- The Kitty config allows remote control. Current config has:

```conf
allow_remote_control socket-only
listen_on unix:/tmp/kitty-{kitty_pid}
```

If remote control is unavailable, click-to-focus should still mostly work through OSC 99 `a=focus`; only the extra `kitty @ focus-window` fallback may fail.

## Troubleshooting

### Extension changes do not apply

Run inside Pi:

```text
/reload
```

### No notification appears after normal agent runs

Possible causes:

1. The Pi split is focused, so it intentionally suppresses the notification.
2. Kitty suppresses due to `o=unfocused`.
3. Pi had queued follow-up/steering messages, so `ctx.hasPendingMessages()` skipped the notification.
4. Not running inside Kitty or not interactive.

Use the forced test:

```text
/kitty-notify-test
```

### Test notification does not appear

Check environment in the Pi shell/window:

```bash
echo $KITTY_WINDOW_ID
echo $KITTY_LISTEN_ON
```

Check Kitty remote control:

```bash
kitty @ ls --self
```

### Click does not focus the right split

Check that `$KITTY_WINDOW_ID` exists and that the focus command works manually:

```bash
kitty @ focus-window --match id:$KITTY_WINDOW_ID --no-response
```

If the command works manually, the fallback should work when Kitty sends an activation report.

### Want notifications even when focused

Normal notifications currently use:

```ts
const occasion = options?.force ? "always" : "unfocused";
```

Change it to always:

```ts
const occasion = "always";
```

Or remove the `getKittyWindowFocused` skip in the `agent_end` handler.

## Verification commands

From a shell:

```bash
cd ~/.pi/agent

tsc extensions/kitty-llm-notify.ts \
  --noEmit \
  --target ES2022 \
  --module NodeNext \
  --moduleResolution NodeNext \
  --types node \
  --typeRoots ~/.pi/agent/npm/node_modules/@types \
  --skipLibCheck \
  --baseUrl /Users/irshath/.nvm/versions/node/v24.15.0/lib/node_modules
```

Smoke-load extension:

```bash
PI_OFFLINE=1 pi --no-extensions -e ~/.pi/agent/extensions/kitty-llm-notify.ts --list-models __no_such_model__
```

Expected result:

```text
No models matching "__no_such_model__"
```

## Future ideas

Possible future tweaks:

- Add settings via environment variables instead of constants.
- Add a `/kitty-notify-toggle` command.
- Add a quiet-hours mode.
- Include model name or cost in the notification body.
- Use different urgency for errors vs normal completion.
- Notify on long-running tool completion, not only `agent_end`.
- Persist user preferences with `pi.appendEntry()` if per-session behavior is wanted.
