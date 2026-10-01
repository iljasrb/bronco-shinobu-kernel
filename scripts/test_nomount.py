#!/usr/bin/env python3
"""Run with python3 scripts/test_nomount.py; no downloads or kernel toolchain."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]

with tempfile.TemporaryDirectory(prefix="shinobu-nomount-") as temporary:
    root = Path(temporary)
    scripts = root / "scripts"
    scripts.mkdir()
    shutil.copy2(repo / "scripts/integrate-nomount.sh", scripts)
    shutil.copy2(repo / "sync-sources.sh", root)
    shutil.copy2(repo / "sources.env", root)
    fs = root / "kernel/fs"
    fs.mkdir(parents=True)
    (fs / "Makefile").write_text("obj-y += open.o\n")
    (fs / "Kconfig").write_text('menu "File systems"\nmenu "Nested"\nendmenu\nendmenu\n')
    source = root / "NoMount/kernel/src"
    source.mkdir(parents=True)
    for name in ("Kconfig", "Makefile", "nomount.c", "nomount.h"):
        (source / name).write_text("# integration input\n")

    def integrate(ok=True):
        result = subprocess.run(
            ["bash", str(scripts / "integrate-nomount.sh")],
            capture_output=True, text=True,
        )
        assert (result.returncode == 0) == ok, result.stdout + result.stderr
        return result

    integrate()
    link = fs / "nomount"
    assert os.readlink(link) == "../../NoMount/kernel/src"
    assert link.resolve() == source
    before = [(fs / name).read_text() for name in ("Makefile", "Kconfig")]
    integrate()
    assert before == [(fs / name).read_text() for name in ("Makefile", "Kconfig")]
    assert before[0].count("obj-$(CONFIG_NOMOUNT) += nomount/") == 1
    assert before[1].endswith('source "fs/nomount/Kconfig"\nendmenu\n')

    link.unlink()
    link.symlink_to("../../wrong-source")
    assert "unexpected NoMount driver link" in integrate(ok=False).stderr
    assert os.readlink(link) == "../../wrong-source"
    link.unlink()
    link.mkdir()
    assert "not a symbolic link" in integrate(ok=False).stderr
    link.rmdir()
    (source / "nomount.c").unlink()
    assert "input is missing" in integrate(ok=False).stderr
    assert not link.exists()

    # Exercise pin updates without contacting GitHub or resetting any tree.
    mock_bin = root / "bin"
    mock_bin.mkdir()
    git = mock_bin / "git"
    git.write_text('#!/bin/sh\nprintf "%s\\t%s\\n" "$TEST_REVISION" "$4"\n')
    git.chmod(0o755)
    original = (root / "sources.env").read_text()
    revision = "1" * 40
    env = dict(os.environ, PATH=f"{mock_bin}:{os.environ['PATH']}", TEST_REVISION=revision)
    command = ["bash", str(root / "sync-sources.sh"), "--pull-latest", "nomount", "--pins-only"]
    subprocess.run(command, env=env, check=True, capture_output=True)
    updated = (root / "sources.env").read_text()
    assert f'NOMOUNT_REVISION="{revision}"' in updated
    assert (root / "sources.env.bak").read_text() == original
    assert updated.splitlines() == [
        f'NOMOUNT_REVISION="{revision}"' if line.startswith("NOMOUNT_REVISION=") else line
        for line in original.splitlines()
    ]
    subprocess.run(command, env=env, check=True, capture_output=True)
    assert (root / "sources.env.bak").read_text() == original
    env["TEST_REVISION"] = "invalid"
    assert subprocess.run(command, env=env, capture_output=True).returncode != 0
    assert (root / "sources.env").read_text() == updated
    env["TEST_REVISION"] = "3" * 40
    command[-2] = "susfs"
    subprocess.run(command, env=env, check=True, capture_output=True)
    assert f'SUSFS_REVISION="{"3" * 40}"' in (root / "sources.env").read_text()
    assert (root / "sources.env.bak").read_text() == updated

    adb = mock_bin / "adb"
    adb.write_text('''#!/bin/sh
case "$*" in
    wait-for-device) exit 0 ;;
    "shell getprop sys.boot_completed") echo 1 ;;
    "shell su -c id") printf '%s\\n' "$TEST_ROOT_ID" ;;
    "shell su -c '/data/adb/modules/nomount/bin/nm version'")
        printf '%s\\n' "$TEST_NOMOUNT_VERSION" ;;
    *) exit 1 ;;
esac
''')
    adb.chmod(0o755)
    command = ["bash", str(repo / "scripts/boot-check.sh"), "nomount"]
    for version, ok in (("20", True), ("unavailable", False)):
        env["TEST_NOMOUNT_VERSION"] = version
        result = subprocess.run(command, env=env, capture_output=True)
        assert (result.returncode == 0) == ok, result.stderr
    command[-1] = "root"
    for identity, ok in (("uid=0(root) context=u:r:ksu:s0", True),
                         ("uid=2000(shell) context=u:r:shell:s0", False)):
        env["TEST_ROOT_ID"] = identity
        result = subprocess.run(command, env=env, capture_output=True)
        assert (result.returncode == 0) == ok, result.stderr

print("PASS: NoMount integration, repeat runs, conflict guards, pin updates and boot check")
