#!/usr/bin/env bash
#
# Cut a release.
#
#   ./scripts/release.sh 0.3.2-1
#
# CI now pushes to main itself (the "Advertise the published version" job), so a
# local checkout goes stale after every release. Tagging from a stale base put
# the tag on divergent history twice, which then needed a force-push to fix.
# This refuses to do that.
#
# Do NOT edit `version` in config.yaml -- the tag is the source of truth and CI
# writes it. See DOCS.md, "Keeping things up to date".

set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    echo "usage: ${0##*/} <version>   e.g. 0.3.2-1" >&2
    exit 2
fi
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+$ ]]; then
    echo "version must look like 0.3.2-1 (upstream-addonrevision)" >&2
    exit 2
fi

cd "$(dirname "${BASH_SOURCE[0]}")/.."

die() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }
ok()  { printf '\033[32m%s\033[0m\n' "$*"; }

# 1. Nothing uncommitted -- otherwise the rebase below silently does nothing.
if [[ -n "$(git status --porcelain)" ]]; then
    git status --short
    die "working tree is dirty; commit or stash first"
fi

# 2. Sync with whatever CI pushed while you were working.
git fetch -q origin
if [[ -n "$(git log --oneline HEAD..origin/main)" ]]; then
    echo "origin/main is ahead; rebasing:"
    git log --oneline HEAD..origin/main | sed 's/^/  /'
    git rebase origin/main
fi
git push -q origin main

# 3. The tag must be reachable from main, or CI builds orphaned history.
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
    die "HEAD is not origin/main after rebase; resolve manually"
fi
if git rev-parse -q --verify "refs/tags/v${VERSION}" >/dev/null; then
    die "tag v${VERSION} already exists locally"
fi

# 4. Lint before tagging. CI runs the same shellcheck, and discovering a
#    warning there means deleting and recreating a tag that already exists.
if command -v docker >/dev/null 2>&1; then
    ./scripts/lint.sh || die "shellcheck failed; fix before tagging"
else
    echo "docker unavailable; skipping local shellcheck (CI will still run it)"
fi

# 5. A changelog entry is part of a release, not an optional extra.
grep -q "^## ${VERSION}\$" paseo/CHANGELOG.md \
    || die "no '## ${VERSION}' section in paseo/CHANGELOG.md"

git tag -a "v${VERSION}" -m "Release ${VERSION}"
git push origin "v${VERSION}"

ok "tagged v${VERSION} at $(git rev-parse --short HEAD)"
echo "CI will build both architectures, publish to GHCR, and only then bump"
echo "config.yaml on main. Watch: gh run watch"
