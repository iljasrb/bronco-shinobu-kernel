#!/usr/bin/env python3
from pathlib import Path
import gzip
import os
import shutil
import subprocess
import tempfile
import textwrap

repo = Path(__file__).resolve().parents[1]


def run(*args, ok=True, **kwargs):
    result = subprocess.run(args, capture_output=True, text=True, timeout=30, **kwargs)
    assert (result.returncode == 0) == ok, result.stdout + result.stderr
    return result.stdout.strip()


with tempfile.TemporaryDirectory(prefix="shinobu-build-") as temporary:
    root = Path(temporary)
    (root / "scripts").mkdir()
    (root / "patches").mkdir()
    shutil.copy2(repo / "sources.env", root)
    for name in ("refresh-susfs.sh", "apply-patches.sh"):
        shutil.copy2(repo / "scripts" / name, root / "scripts")
    upstream = root / "upstream"
    hooks = upstream / "50_add_susfs_in_gki-android13-5.10.patch"
    upstream.mkdir()
    hooks.write_text("diff --git a/example b/example\n--- a/example\n+++ b/example\n"
                     "@@ -1 +1 @@\n-old\n+new\n")
    for name in ("fs/susfs.c", "include/linux/susfs.h", "include/linux/susfs_def.h"):
        file = upstream / name
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text("test source\n")
    mock_bin = root / "bin"
    mock_bin.mkdir()
    curl = mock_bin / "curl"
    curl.write_text('''#!/bin/sh
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) output="$2"; shift ;;
        */kernel_patches/*) url="$1" ;;
    esac
    shift
done
cp "$TEST_UPSTREAM/${url##*/kernel_patches/}" "$output"
''')
    curl.chmod(0o755)
    env = dict(os.environ, PATH=f"{mock_bin}:{os.environ['PATH']}", TEST_UPSTREAM=str(upstream))
    refresh = str(root / "scripts/refresh-susfs.sh")
    run("bash", refresh, "--check", env=env, ok=False)
    run("bash", refresh, env=env)
    patch = root / "patches/0001-susfs.patch"
    generated = patch.read_bytes()
    run("bash", refresh, "--check", env=env)
    run("bash", refresh, env=env)
    assert patch.read_bytes() == generated
    hooks.write_text("not a patch\n")
    run("bash", refresh, env=env, ok=False)
    assert patch.read_bytes() == generated

    kernel = root / "kernel"
    run("git", "init", "-q", str(kernel))
    (kernel / "example").write_text("old\n")
    apply = str(root / "scripts/apply-patches.sh")
    run("bash", apply)
    run("bash", apply)
    assert (kernel / "example").read_text() == "new\n"
    patch.write_bytes(generated.replace(b"# SUSFS_REVISION=", b"# WRONG_REVISION="))
    run("bash", apply, ok=False)
    assert (kernel / "example").read_text() == "new\n"

    # Test sparse source checkout and preservation of edits on failed fetches.
    seed = root / "seed"
    run("git", "init", "-q", str(seed))
    run("git", "-C", str(seed), "config", "uploadpack.allowFilter", "true")
    for name in ("clang-needed/bin/clang", "unused/bin/clang"):
        file = seed / name
        file.parent.mkdir(parents=True)
        file.write_text("compiler\n")
    run("git", "-C", str(seed), "add", ".")
    run("git", "-C", str(seed), "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
        "commit", "-qm", "source")
    revision = run("git", "-C", str(seed), "rev-parse", "HEAD")
    sync = (repo / "sync-sources.sh").read_text()
    latest = sync.split("latest_revision() {", 1)[1].split("\nlatest_lineage_updates() {", 1)[0]
    for tag, annotated in (("lightweight", False), ("annotated", True)):
        args = ("-a", "-m", "tag") if annotated else ()
        run("git", "-C", str(seed), "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
            "tag", *args, tag)
        script = 'latest_revision() {' + latest + '\nlatest_revision "$1" "$2"\n'
        assert run("bash", "-c", script, "test", seed.as_uri(), tag) == revision
    function = sync.split("prepare_repository() {", 1)[1].split('\nif [[ -n "$pull_target" ]]', 1)[0]
    script = ('set -euo pipefail\nroot_dir="$1"\nprepare_repository() {' + function +
              '\nprepare_repository tools/android-clang "$2" "$3" clang-needed\n')
    command = ("bash", "-c", script, "test", str(root), seed.as_uri(), revision)
    run(*command)
    checkout = root / "tools/android-clang"
    assert (checkout / "clang-needed/bin/clang").is_file()
    assert not (checkout / "unused").exists()
    compiler = checkout / "clang-needed/bin/clang"
    compiler.write_text("local edit\n")
    run(*command[:-1], "2" * 40, ok=False)
    assert compiler.read_text() == "local edit\n"
    run(*command)
    assert compiler.read_text() == "compiler\n"

    workflow = (repo / ".github/workflows/build.yml").read_text()
    assert "\n  tag:" not in workflow and "git push" not in workflow
    assert "branches: [main, dev]" in workflow and "    paths:" not in workflow
    publish = workflow.split("\n  publish:\n", 1)[1]
    assert "    if: startsWith(github.ref, 'refs/tags/')\n" in publish
    assert "          path: out\n" not in publish
    assert "            inputs/boot.img\n" in workflow
    assert "            out/.config\n" in workflow and "include-hidden-files: true" in workflow
    verify = workflow.split("      - name: Verify release version\n", 1)[1].split("\n      - name:", 1)[0]
    verify = textwrap.dedent(verify.split("run: |\n", 1)[1])
    for tag, ok in (("v0.2.2", True), ("v9.9.9", False)):
        (root / "sources.env").write_text('PROJECT_VERSION="0.2.2"\n')
        run("bash", "-c", verify, cwd=root, env=dict(os.environ, GITHUB_REF_NAME=tag), ok=ok)

    build = (repo / "scripts/build-kernel.sh").read_text()
    guard = 'for option in ' + build.split('for option in ', 1)[1].split('\nrm -f ', 1)[0]
    config = ["CONFIG_KSU=y", "CONFIG_KSU_SUSFS=y", "CONFIG_KEYS=y", "CONFIG_NOMOUNT=y"]
    for missing in (None, *config):
        (root / ".config").write_text("\n".join(line for line in config if line != missing) + "\n")
        run("bash", "-c", 'set -eu; out_dir="$1"; ' + guard, "test", str(root), ok=missing is None)

    packaging = (repo / "scripts/make-boot-image.sh").read_text()
    extract = packaging.split("input_kernel_release=", 1)[1].split("<<'PY'\n", 1)[1].split("\nPY\n", 1)[0]
    raw = b"prefix Linux version 5.10.123-test (builder) suffix"
    for data in (raw, gzip.compress(raw)):
        image = root / "image"
        image.write_bytes(data)
        assert run("python3", "-c", extract, str(image)) == "5.10.123-test"
    image.write_bytes(b"invalid kernel")
    run("python3", "-c", extract, str(image), ok=False)

print("PASS: SUSFS reproduction, pin guard, sparse checkout, dev CI, release tags and gzip kernels")
