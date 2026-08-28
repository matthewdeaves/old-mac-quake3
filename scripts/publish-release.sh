#!/usr/bin/env bash
#
# publish-release.sh - publish the client DMG and/or the Linux server tarball
# as GitHub releases, so a build stops being "cut by hand" (issue #22).
#
# Policy this implements (user, 2026-08-28, issue #22): "only ever have 1
# latest release" per repo. GitHub itself enforces this - exactly one release
# in a repo can be flagged Latest at any time, and creating a new release
# with --latest automatically clears the flag on whichever one held it. This
# script never deletes a GitHub release (deleting one is reserved to the
# user, GRANTS.md) - it only ever CREATES new, properly versioned ones, using
# --latest so the flag moves forward on its own. Old releases stay reachable
# by their own tag; nothing is pruned server-side.
#
# usage: scripts/publish-release.sh <client|server|both> <version>
#   client: uploads dist/ioquake3-OldMac-<version>.dmg, tag <version>, --latest
#   server: uploads every dist/server/quake3-server-<version>-linux-*.tar.gz,
#           tag server-<version>, NOT --latest (client always holds Latest)
#
# pre: gh auth login already done on this workstation; the artifact(s) already
#      built (scripts/make-dmg.sh / scripts/build-server-linux.sh).
# post: a real release exists on GitHub for the requested kind(s), and stale
#       local dist/ builds for OTHER versions of the same kind are removed
#       (LOCAL disk hygiene only - never touches anything already published).
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
REPO_SLUG="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)"
[ -n "$REPO_SLUG" ] || { echo "publish-release: gh repo view failed - not authenticated or wrong dir?" >&2; exit 1; }

KIND="${1:?usage: $0 <client|server|both> <version>}"
VERSION="${2:?usage: $0 <client|server|both> <version>}"

case "$KIND" in
  client|server|both) ;;
  *) echo "publish-release: kind must be client, server or both (got '$KIND')" >&2; exit 2 ;;
esac

# A release published from a dirty tree cannot be rebuilt from its own tag
# later - same rule build-server-linux.sh already enforces for the server
# tarball itself; enforced here too because this is the actual publish step.
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  echo "publish-release: working tree is dirty - commit or stash first." >&2
  echo "  A published release must be reproducible from its tag." >&2
  exit 1
fi

publish_client() {
  local dmg="$REPO_ROOT/dist/ioquake3-OldMac-$VERSION.dmg"
  [ -f "$dmg" ] || { echo "publish-release: missing $dmg - run scripts/make-dmg.sh $VERSION" >&2; exit 1; }

  if gh release view "$VERSION" -R "$REPO_SLUG" >/dev/null 2>&1; then
    echo "[publish-release] client: release $VERSION already exists, uploading asset (--clobber)"
    gh release upload "$VERSION" "$dmg" -R "$REPO_SLUG" --clobber
    gh release edit "$VERSION" -R "$REPO_SLUG" --latest
  else
    echo "[publish-release] client: creating release $VERSION (--latest)"
    gh release create "$VERSION" "$dmg" -R "$REPO_SLUG" \
      --title "ioquake3 OldMac $VERSION" \
      --notes "$(git log -1 --format='Built from %H%n%n%s')" \
      --latest
  fi

  # Local disk hygiene only (issue #22's "10 tarballs going back to v0.5.0"
  # complaint applied to dist/server/, the same clutter exists for dist/
  # client DMGs). dist/ is gitignored; this never touches anything published.
  find "$REPO_ROOT/dist" -maxdepth 1 -name 'ioquake3-OldMac-*.dmg' \
    ! -name "ioquake3-OldMac-$VERSION.dmg" -print -delete 2>/dev/null || true
}

publish_server() {
  local tag="server-$VERSION"
  local tarballs=("$REPO_ROOT"/dist/server/quake3-server-"$VERSION"-linux-*.tar.gz)
  [ -e "${tarballs[0]}" ] || {
    echo "publish-release: no dist/server/quake3-server-$VERSION-linux-*.tar.gz" >&2
    echo "  run scripts/build-server-linux.sh --version $VERSION [--arch ...]" >&2
    exit 1
  }

  if gh release view "$tag" -R "$REPO_SLUG" >/dev/null 2>&1; then
    echo "[publish-release] server: release $tag already exists, uploading assets (--clobber)"
    gh release upload "$tag" "${tarballs[@]}" -R "$REPO_SLUG" --clobber
  else
    echo "[publish-release] server: creating release $tag (not --latest - client holds Latest)"
    gh release create "$tag" "${tarballs[@]}" -R "$REPO_SLUG" \
      --title "Linux dedicated server $VERSION" \
      --notes "$(git log -1 --format='Built from %H%n%n%s')"
  fi

  # Local disk hygiene, same reasoning as publish_client. Every arch for
  # OTHER versions goes; every arch for THIS version stays.
  find "$REPO_ROOT/dist/server" -maxdepth 1 -name 'quake3-server-*-linux-*.tar.gz' \
    ! -name "quake3-server-$VERSION-linux-*.tar.gz" -print -delete 2>/dev/null || true
}

case "$KIND" in
  client) publish_client ;;
  server) publish_server ;;
  both)   publish_client; publish_server ;;
esac

echo "[publish-release] done"
gh release list -R "$REPO_SLUG" --limit 10
