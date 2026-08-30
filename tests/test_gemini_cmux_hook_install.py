#!/usr/bin/env python3
"""
Behavioral tests for scripts/install-gemini-cmux-hook.sh:
- Tests transparent launcher behavior for native `cmux hooks setup antigravity --yes`
- Tests failure when cmux is missing from PATH
- Tests installation executes `cmux hooks setup antigravity --yes`
- Tests uninstallation executes `cmux hooks uninstall antigravity --yes`
- Tests exit codes and stdout/stderr from cmux are preserved
- Tests script does not parse or write ~/.gemini files itself (real settings untouched)
"""

from __future__ import annotations

import json
import os
import stat
import subprocess
from pathlib import Path
import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
INSTALLER_SCRIPT = REPO_ROOT / "scripts" / "install-gemini-cmux-hook.sh"


@pytest.fixture
def test_env(tmp_path: Path) -> tuple[Path, Path, Path, dict[str, str]]:
    test_home = tmp_path / "home"
    test_home.mkdir(parents=True, exist_ok=True)
    bin_dir = test_home / "bin"
    bin_dir.mkdir(parents=True, exist_ok=True)
    cmux_log = test_home / "cmux_calls.log"

    env = os.environ.copy()
    env["HOME"] = str(test_home)
    env["PATH"] = f"{bin_dir}:{env.get('PATH', '')}"
    return test_home, bin_dir, cmux_log, env


def create_mock_cmux(bin_dir: Path, log_file: Path, exit_code: int = 0, stdout_msg: str = "", stderr_msg: str = "") -> Path:
    mock_cmux = bin_dir / "cmux"
    lines = [
        "#!/usr/bin/env bash",
        "set -euo pipefail",
        f'printf "%s\\n" "cmux args: $*" >> "{log_file}"',
    ]
    if stdout_msg:
        lines.append(f'printf "%s\\n" "{stdout_msg}"')
    if stderr_msg:
        lines.append(f'printf "%s\\n" "{stderr_msg}" >&2')
    lines.append(f"exit {exit_code}")
    lines.append("")
    mock_cmux.write_text("\n".join(lines), encoding="utf-8")
    mock_cmux.chmod(mock_cmux.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return mock_cmux


def test_missing_cmux_fails_cleanly(test_env: tuple[Path, Path, Path, dict[str, str]]) -> None:
    test_home, bin_dir, cmux_log, env = test_env
    clean_paths = [
        p for p in env.get("PATH", "").split(":")
        if p and not Path(p, "cmux").exists() and p != str(bin_dir)
    ]
    env["PATH"] = ":".join(clean_paths)

    proc = subprocess.run(
        [str(INSTALLER_SCRIPT)],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    assert proc.returncode != 0
    assert "cmux binary not found" in proc.stderr


def test_install_invokes_native_cmux_setup_antigravity(test_env: tuple[Path, Path, Path, dict[str, str]]) -> None:
    test_home, bin_dir, cmux_log, env = test_env
    create_mock_cmux(bin_dir, cmux_log, stdout_msg="Antigravity hooks installed at ~/.gemini/config/hooks.json")

    proc = subprocess.run(
        [str(INSTALLER_SCRIPT)],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    assert proc.returncode == 0
    assert "Antigravity hooks installed" in proc.stdout

    log_content = cmux_log.read_text(encoding="utf-8")
    assert "cmux args: hooks setup antigravity --yes" in log_content

    assert not (test_home / ".gemini" / "settings.json").exists()


def test_uninstall_invokes_native_cmux_uninstall_antigravity(test_env: tuple[Path, Path, Path, dict[str, str]]) -> None:
    test_home, bin_dir, cmux_log, env = test_env
    create_mock_cmux(bin_dir, cmux_log, stdout_msg="Antigravity hooks removed")

    for flag in ["--uninstall", "-u", "uninstall"]:
        cmux_log.unlink(missing_ok=True)
        proc = subprocess.run(
            [str(INSTALLER_SCRIPT), flag],
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )
        assert proc.returncode == 0
        assert "Antigravity hooks removed" in proc.stdout
        log_content = cmux_log.read_text(encoding="utf-8")
        assert "cmux args: hooks uninstall antigravity --yes" in log_content


def test_cmux_failure_preserves_exit_code_and_stderr(test_env: tuple[Path, Path, Path, dict[str, str]]) -> None:
    test_home, bin_dir, cmux_log, env = test_env
    create_mock_cmux(bin_dir, cmux_log, exit_code=42, stderr_msg="cmux failed to install hook")

    proc = subprocess.run(
        [str(INSTALLER_SCRIPT)],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    assert proc.returncode == 42
    assert "cmux failed to install hook" in proc.stderr


def test_existing_user_settings_remain_untouched(test_env: tuple[Path, Path, Path, dict[str, str]]) -> None:
    test_home, bin_dir, cmux_log, env = test_env
    gemini_dir = test_home / ".gemini"
    gemini_dir.mkdir(parents=True, exist_ok=True)
    settings_file = gemini_dir / "settings.json"
    initial_content = json.dumps({"customKey": "keep_this", "general": {"telemetry": False}}, indent=2)
    settings_file.write_text(initial_content, encoding="utf-8")

    create_mock_cmux(bin_dir, cmux_log, stdout_msg="ok")
    proc = subprocess.run(
        [str(INSTALLER_SCRIPT)],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    assert proc.returncode == 0
    assert settings_file.read_text(encoding="utf-8") == initial_content


def test_help_flag_displays_usage(test_env: tuple[Path, Path, Path, dict[str, str]]) -> None:
    test_home, bin_dir, cmux_log, env = test_env
    for flag in ["-h", "--help"]:
        proc = subprocess.run(
            [str(INSTALLER_SCRIPT), flag],
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )
        assert proc.returncode == 0
        assert "cmux hooks setup antigravity" in proc.stdout
        assert "~/.gemini/config/hooks.json" in proc.stdout
