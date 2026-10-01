#!/usr/bin/env bash
set -euo pipefail
readonly root_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$root_dir/sources.env"
[[ $# == 0 || ( $# == 1 && $1 == --check ) ]] || {
    printf '%s\n' 'Usage: scripts/refresh-susfs.sh [--check]' >&2
    exit 2
}
[[ "$SUSFS_REVISION" =~ ^[0-9a-f]{40}$ ]] || exit 2
readonly work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
readonly hooks="50_add_susfs_in_${SUSFS_BRANCH}.patch"
for file in "$hooks" fs/susfs.c include/linux/susfs.h include/linux/susfs_def.h; do
    mkdir -p "$work_dir/$(dirname "$file")"
    curl -fsSL --retry 3 --max-time 60 \
        "${SUSFS_REPOSITORY%.git}/-/raw/$SUSFS_REVISION/kernel_patches/$file" \
        -o "$work_dir/$file"
done

python3 - "$work_dir" "$hooks" "$SUSFS_REVISION" "$root_dir/patches/0001-susfs.patch" "${1:-}" <<'PY'
from pathlib import Path
import re
import subprocess
import sys

work, hooks, revision, output, mode = sys.argv[1:]
work, output = Path(work), Path(output)
sections = re.split(r"(?=^diff --git )", (work / hooks).read_text(), flags=re.MULTILINE)
patches = [section for section in sections if section.startswith("diff --git ")]
if not patches:
    raise SystemExit("upstream patch contains no diffs")
for name in ("fs/susfs.c", "include/linux/susfs.h", "include/linux/susfs_def.h"):
    result = subprocess.run(
        ["git", "diff", "--no-index", "--no-ext-diff", "--no-textconv", "--no-color",
         "--full-index", "--src-prefix=a/", "--dst-prefix=b/", "/dev/null", name],
        cwd=work, capture_output=True, text=True,
    )
    if result.returncode != 1:
        raise SystemExit(result.stderr or f"could not generate diff for {name}")
    patches.append(result.stdout)
patches.sort(key=lambda section: section.splitlines()[0])
text = f"# SUSFS_REVISION={revision}\n" + "".join(patches)
subprocess.run(["git", "apply", "--numstat"], input=text, text=True,
               stdout=subprocess.DEVNULL, check=True)
if mode == "--check":
    if not output.is_file() or output.read_text() != text:
        raise SystemExit("SUSFS patch differs: run scripts/refresh-susfs.sh and review the diff")
    print("SUSFS patch matches its pinned upstream source")
else:
    temporary = output.with_name(f".{output.name}.tmp")
    temporary.write_text(text)
    temporary.replace(output)
    print(f"Regenerated {output}")
PY
