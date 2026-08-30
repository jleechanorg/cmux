# Antigravity cmux Hook Launcher

## Overview & Scope

`scripts/install-gemini-cmux-hook.sh` is a transparent, non-destructive convenience launcher that invokes native cmux hook management for Google Antigravity (`agy`).

cmux provides native, first-class support for Antigravity via `cmux hooks setup antigravity --yes`. This launcher script validates that `cmux` is available on `PATH`, executes the native command with non-interactive confirmation, and transparently preserves exit codes, standard output, and standard error.

> [!NOTE]
> This installer is a lightweight convenience wrapper around official cmux Antigravity support, not a temporary workaround. It does not parse, modify, or overwrite any configuration files directly.

---

## Native Antigravity Integration

Antigravity stores its hook configurations natively in `~/.gemini/config/hooks.json`.

### Direct cmux CLI Commands

You can configure or remove Antigravity hooks directly using `cmux`:

- **Install / Setup**:
  ```bash
  cmux hooks setup antigravity --yes
  # or using the agy alias:
  cmux hooks setup agy --yes
  ```

- **Uninstall**:
  ```bash
  cmux hooks uninstall antigravity --yes
  # or using the agy alias:
  cmux hooks uninstall agy --yes
  ```

### Launcher Script Usage

Alternatively, run the convenience script:

- **Setup**:
  ```bash
  ./scripts/install-gemini-cmux-hook.sh
  ```

- **Uninstall**:
  ```bash
  ./scripts/install-gemini-cmux-hook.sh --uninstall
  ```

- **Help**:
  ```bash
  ./scripts/install-gemini-cmux-hook.sh --help
  ```

---

## Distinction: Antigravity vs. Gemini CLI

- **Antigravity (`agy`)**: Uses `~/.gemini/config/hooks.json` with the `antigravityJSON` schema (events: `SessionStart`, `PreInvocation`, `Stop`, `turn-completion`, `Notification`, `SessionEnd`).
- **Gemini CLI**: Separately uses `~/.gemini/settings.json` with nested command hooks (including `AfterAgent`, `BeforeAgent`, `SessionStart`, `SessionEnd`), managed natively via `cmux hooks setup gemini --yes`.

The `install-gemini-cmux-hook.sh` launcher targets Antigravity and does not create or modify `~/.gemini/settings.json`.

---

## Verification & Testing

Automated behavioral tests verify execution with mock binaries under temporary `HOME` environments:

```bash
# Run python test suite
pytest -v tests/test_gemini_cmux_hook_install.py

# Run direct bash test suite
bash tests/test_install_gemini_cmux_hook.sh
```
