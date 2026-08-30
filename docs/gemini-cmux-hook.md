# Google Antigravity cmux Hook Integration

cmux natively supports Google Antigravity (AGY) agent lifecycle hooks for turn-completion notifications, session tracking, and status updates.

---

## Native Antigravity Hook Architecture

- **Native Support**: cmux includes first-class native support for Antigravity (`antigravity`, alias: `agy`).
- **Configuration Path**: `~/.gemini/config/hooks.json`
- **Native CLI Commands**:
  - Install: `cmux hooks setup antigravity --yes` (or `cmux hooks antigravity install --yes`)
  - Uninstall: `cmux hooks uninstall antigravity --yes` (or `cmux hooks antigravity uninstall --yes`)
- **Lifecycle Events**:
  - `SessionStart` &rarr; `session-start`
  - `PreInvocation` &rarr; `prompt-submit`
  - `Stop` &rarr; `stop`
  - `turn-completion` &rarr; `stop`
  - `Notification` &rarr; `notification`
  - `SessionEnd` &rarr; `session-end`
- **Safe Completion Notifications**: Hooks use pinned dispatch (`cmux-antigravity-hook-v2`) to trigger generic turn-completion notifications (`cmux notify`). Hook invocations never capture, inspect, log, or forward user prompts, context tokens, workspace files, task payloads, stdin data, or environment secrets.
- **Separate Gemini CLI Integration**: Gemini CLI hooks use `~/.gemini/settings.json` via `cmux hooks setup gemini` / `cmux hooks uninstall gemini`. Antigravity hooks use `~/.gemini/config/hooks.json`; `settings.json` is a separate integration that remains completely untouched.

---

## Compatibility & Convenience Launcher

The repository provides an optional convenience launcher script at [`/Users/jleechan/projects_reference/cmux-worktrees/gemini-antigravity-hook/scripts/install-gemini-cmux-hook.sh`](file:///Users/jleechan/projects_reference/cmux-worktrees/gemini-antigravity-hook/scripts/install-gemini-cmux-hook.sh).

This script is an optional convenience wrapper that checks that `cmux` is available on `PATH` and directly executes:

```bash
cmux hooks setup antigravity --yes
```

It performs no direct filesystem modifications and does not read or write `~/.gemini/settings.json` or `~/.gemini/config/hooks.json`.

### Usage

```bash
./scripts/install-gemini-cmux-hook.sh
```

---

## Native Uninstallation

To remove native Antigravity hooks from `~/.gemini/config/hooks.json`, run:

```bash
cmux hooks uninstall antigravity --yes
```

---

## Automated Verification

The integration behavior is verified by the standalone test script at [`/Users/jleechan/projects_reference/cmux-worktrees/gemini-antigravity-hook/tests/test_install_gemini_cmux_hook.sh`](file:///Users/jleechan/projects_reference/cmux-worktrees/gemini-antigravity-hook/tests/test_install_gemini_cmux_hook.sh):

```bash
bash tests/test_install_gemini_cmux_hook.sh
```

