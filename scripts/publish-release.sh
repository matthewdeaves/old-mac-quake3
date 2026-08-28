#!/usr/bin/env bash
#
# publish-release.sh <version> [--yes] - publish ONE release and prune older ones.
#
# The user's rule, from issue #21: "for servers and fat binaries we only host the
# latest build as latest release, we are not interested in historical releases
# for server binaries or fat binaries". Nothing in scripts/ did any of this, so
# releases were made by hand and nothing ever removed an old one. Issue #22.
#
# TWO INDEPENDENT STREAMS, pruned separately:
#   app     tag vX.Y.Z          asset dist/ioquake3-OldMac-<version>.dmg
#   server  tag server-vX.Y.Z   assets dist/server/quake3-server-<version>-linux-*.tar.gz
#
# A version is EITHER an app version or a server version, decided by the tag
# prefix, and only that stream is touched. Publishing an app release must never
# delete the server one; they move at different rates and the server release is
# what retro-server-infra pulls.
#
# DRY RUN BY DEFAULT. Nothing is uploaded and nothing is deleted without --yes.
# Deleting a published release is irreversible and outward-facing: anyone who has
# the URL loses it, and this script cannot tell a release nobody wants from one
# somebody is mid-download of. So the default prints the plan and stops.
#
set -euo pipefail

VERSION="${1:?usage: publish-release.sh <version> [--yes]   e.g. v0.6.6 or server-v0.6.6}"
shift || true
CONFIRM=0
ALLOW_DOWNGRADE=0
for a in "$@"; do
  case "$a" in
    --yes) CONFIRM=1 ;;
    --allow-downgrade) ALLOW_DOWNGRADE=1 ;;
    *) echo "publish-release.sh: unknown argument: $a" >&2; exit 2 ;;
  esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
REPO="matthewdeaves/old-mac-quake3"

case "$VERSION" in
  server-v*) STREAM=server ;;
  v*)        STREAM=app ;;
  *) echo "publish-release.sh: version must start with 'v' or 'server-v' (got: $VERSION)" >&2; exit 2 ;;
esac

# ---- gather the assets this stream ships ----------------------------------
ASSETS=()
if [ "$STREAM" = app ]; then
  DMG="$REPO_ROOT/dist/ioquake3-OldMac-$VERSION.dmg"
  [ -f "$DMG" ] || { echo "publish-release.sh: no $DMG - run scripts/make-dmg.sh $VERSION on a Tiger G4" >&2; exit 1; }
  ASSETS=("$DMG")
  TITLE="ioquake3 OldMac $VERSION"
else
  # The TAG carries the server- prefix but the TARBALL does not:
  # tag server-v0.6.3 ships quake3-server-v0.6.3-linux-x86_64.tar.gz. Checked
  # against what is actually in dist/server/ rather than assumed.
  ASSET_VER="${VERSION#server-}"
  while IFS= read -r f; do ASSETS+=("$f"); done < <(ls -1 "$REPO_ROOT"/dist/server/quake3-server-"$ASSET_VER"-linux-*.tar.gz 2>/dev/null || true)
  [ "${#ASSETS[@]}" -gt 0 ] || { echo "publish-release.sh: no dist/server/quake3-server-$ASSET_VER-linux-*.tar.gz - run scripts/build-server-linux.sh" >&2; exit 1; }
  TITLE="Linux dedicated server $ASSET_VER"
fi

# A dirty or wrong-tree build must not be published. build-server-linux.sh
# already refuses to BUILD one (d6c94027); this is the same gate at the point of
# publishing, because the tarball on disk may predate that check.
# Gates the real publish only. A dry run is a read, and refusing to even show
# the plan on a dirty tree would make this useless exactly when it is wanted.
if [ "$CONFIRM" = 1 ] && [ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]; then
  echo "publish-release.sh: working tree is dirty; commit or stash before publishing" >&2
  exit 1
fi

# ---- work out what would be pruned ----------------------------------------
# Only tags in THIS stream. The app stream must exclude server-v*, which a naive
# 'v*' match would otherwise sweep up and delete.
# --json, not column-position parsing: `gh release list` puts a Latest marker in
# a middle column on some rows and not others, so $(NF-1) reads a different field
# depending on the row and would return a title word as a tag.
EXISTING=$(gh release list -R "$REPO" --limit 100 --json tagName --jq '.[].tagName' 2>/dev/null || true)
PRUNE=()
while IFS= read -r tag; do
  [ -n "$tag" ] || continue
  [ "$tag" = "$VERSION" ] && continue
  case "$STREAM:$tag" in
    server:server-v*) PRUNE+=("$tag") ;;
    app:server-v*)    ;;                 # other stream, leave alone
    app:v*)           PRUNE+=("$tag") ;;
  esac
done <<< "$EXISTING"

echo "== publish-release $VERSION (stream: $STREAM) =="
echo "release title : $TITLE"
echo "assets:"
for a in "${ASSETS[@]}"; do echo "    $(basename "$a")  $(shasum -a 256 "$a" | cut -d' ' -f1)"; done
if [ "${#PRUNE[@]}" -gt 0 ]; then
  echo "would DELETE these older $STREAM releases:"
  for t in "${PRUNE[@]}"; do echo "    $t"; done
else
  echo "no older $STREAM releases to delete"
fi

# REFUSE TO DELETE SOMETHING NEWER THAN WHAT IS BEING PUBLISHED.
#
# "Only host the latest" plus "delete everything else in the stream" means that
# publishing an OLD version quietly destroys the newer one. Caught while testing
# this script: a dry run of v0.6.4 offered to delete v0.6.5. That is a plausible
# thing to type by mistake and there is no undo.
#
# sort -V, so v0.6.10 is correctly newer than v0.6.9, which a string compare gets
# wrong.
NEWER=()
for t in ${PRUNE[@]+"${PRUNE[@]}"}; do
  if [ "$(printf '%s\n%s\n' "$VERSION" "$t" | sort -V | tail -1)" = "$t" ]; then
    NEWER+=("$t")
  fi
done
if [ "${#NEWER[@]}" -gt 0 ] && [ "$ALLOW_DOWNGRADE" != 1 ]; then
  echo
  echo "REFUSING: these existing releases are NEWER than $VERSION:" >&2
  for t in "${NEWER[@]}"; do echo "    $t" >&2; done
  echo "Publishing $VERSION would delete them. If that is genuinely what you want," >&2
  echo "re-run with --allow-downgrade." >&2
  exit 1
fi

if [ "$CONFIRM" != 1 ]; then
  echo
  echo "DRY RUN. Nothing uploaded, nothing deleted."
  echo "Deleting a release is irreversible and public. Re-run with --yes to do it."
  exit 0
fi

# ---- act ------------------------------------------------------------------
if gh release view "$VERSION" -R "$REPO" >/dev/null 2>&1; then
  echo "==> release $VERSION exists; replacing its assets"
  gh release upload "$VERSION" "${ASSETS[@]}" -R "$REPO" --clobber
else
  echo "==> creating release $VERSION"
  gh release create "$VERSION" "${ASSETS[@]}" -R "$REPO" --title "$TITLE" --generate-notes
fi

for t in "${PRUNE[@]}"; do
  echo "==> deleting old $STREAM release $t"
  gh release delete "$t" -R "$REPO" --yes
done

echo "==> done. $VERSION is the only $STREAM release."
