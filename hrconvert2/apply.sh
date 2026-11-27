#!/bin/bash
# HRConvert2's build of PyMeshLab. Applies HRConvert2's patches to the sources PyMeshLab 2025.7.post1 pins, once.
#
#   git submodule update --init --recursive
#   bash hrconvert2/apply.sh
#
# Then build as PyMeshLab builds, with scripts/Linux/1_build.sh & scripts/Linux/2_deploy.sh.
#
# It checks that MeshLab & vcglib are at the commits PyMeshLab pins, & applies the patches for each with git apply,
# which refuses a patch that does not apply exactly. MeshLab builds lib3ds & OpenCTM from archives it downloads
# unpatched, so this fetches the same releases from Debian's archive, checks each by SHA-256, unpacks it where
# MeshLab's build looks before it downloads its own, & patches it with patch, allowing no fuzz. Every file a patch
# touches must then match patched.sha256, which holds the files as they were tested. It writes .hrconvert2-patched
# at the root last, & src/CMakeLists.txt refuses to configure without it. It changes nothing outside the source tree.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
HRC=$ROOT/hrconvert2
MESHLAB=$ROOT/src/meshlab
VCGLIB=$MESHLAB/src/vcglib
DOWNLOADS=$MESHLAB/src/external/downloads
MARKER=$ROOT/.hrconvert2-patched

MESHLAB_PIN=d876376e3cc4f92d257e248023d82cbac5b03c7d
VCGLIB_PIN=c94ef4e12e9ea3ae986d9af91005be8328d13719

LIB3DS_ARCHIVE=lib3ds_1.3.0.orig.tar.gz
LIB3DS_FOLDER=lib3ds-1.3.0
LIB3DS_SHA256=0c0340d587fe9a8ac054cc3e6b1eac43973a85ba85aff716a85038d2f0f7a6c0
LIB3DS_URLS=(
  "https://deb.debian.org/debian/pool/main/l/lib3ds/$LIB3DS_ARCHIVE"
  "https://snapshot.debian.org/file/856b89621464f5721263999e7a7a665961fefac7"
  "http://archive.ubuntu.com/ubuntu/pool/universe/l/lib3ds/$LIB3DS_ARCHIVE")

OPENCTM_ARCHIVE=openctm_1.0.3+dfsg1.orig.tar.bz2
OPENCTM_FOLDER=OpenCTM-1.0.3
OPENCTM_SHA256=b72bae806d65dcb4d55b88f17bb636c9908717871cbebff6c32024399f50a074
OPENCTM_URLS=(
  "https://deb.debian.org/debian/pool/main/o/openctm/$OPENCTM_ARCHIVE"
  "https://snapshot.debian.org/file/f36c7774128e409ec032b13a57bda29e1ffc3f6d"
  "http://archive.ubuntu.com/ubuntu/pool/universe/o/openctm/$OPENCTM_ARCHIVE")

fail() { echo "hrconvert2/apply.sh: $*" >&2; exit 1; }

for tool in git curl patch sha256sum tar; do
  command -v "$tool" > /dev/null || fail "$tool is not installed."
done

# Fetches an archive from the first source that serves the expected bytes. A folder named by HRCONVERT2_ARCHIVES,
# for a build without the network, is tried first. Usage: fetch <out file> <sha256> <url> ...
fetch() {
  local out=$1 expected=$2; shift 2
  local url
  [ -n "${HRCONVERT2_ARCHIVES:-}" ] && set -- "file://$HRCONVERT2_ARCHIVES/$(basename "$out")" "$@"
  for url in "$@"; do
    if curl -fsSL --retry 3 --connect-timeout 30 -o "$out" "$url" && [ "$(sha256sum "$out" | cut -d' ' -f1)" = "$expected" ]; then
      echo "Fetched $(basename "$out") from $url, SHA-256 $expected."
      return 0
    fi
    echo "Not usable: $url" >&2
  done
  fail "no source served $(basename "$out") with SHA-256 $expected."
}

# Applies a folder of patches, in order, to a git checkout.
apply_to_checkout() {
  local tree=$1 folder=$2
  local patch
  for patch in "$folder"/*.patch; do
    git -C "$tree" apply --whitespace=nowarn "$patch" || fail "$(basename "$patch") does not apply to $tree."
    echo "Applied $(basename "$folder")/$(basename "$patch")."
  done
}

# Applies a folder of patches, in order, to an unpacked archive. The archive sits inside MeshLab's checkout, where git
# apply would skip paths as outside the current folder, so patch applies them, with no fuzz.
apply_to_archive() {
  local tree=$1 folder=$2
  local patch
  for patch in "$folder"/*.patch; do
    patch -p1 --batch --forward --fuzz=0 --no-backup-if-mismatch --quiet -d "$tree" -i "$patch" || fail "$(basename "$patch") does not apply to $tree."
    echo "Applied $(basename "$folder")/$(basename "$patch")."
  done
}

[ -e "$MARKER" ] && fail "the patches are applied already. Start again from a clean checkout."
[ "$(git -C "$MESHLAB" rev-parse HEAD)" = "$MESHLAB_PIN" ] || fail "src/meshlab is not at $MESHLAB_PIN. Run git submodule update --init --recursive."
[ "$(git -C "$VCGLIB" rev-parse HEAD)" = "$VCGLIB_PIN" ] || fail "src/meshlab/src/vcglib is not at $VCGLIB_PIN. Run git submodule update --init --recursive."
[ -z "$(git -C "$MESHLAB" status --porcelain --untracked-files=no)" ] || fail "src/meshlab has changes. Start again from a clean checkout."
[ -z "$(git -C "$VCGLIB" status --porcelain --untracked-files=no)" ] || fail "src/meshlab/src/vcglib has changes. Start again from a clean checkout."
[ -e "$DOWNLOADS/$LIB3DS_FOLDER" ] && fail "$DOWNLOADS/$LIB3DS_FOLDER exists. MeshLab would build it unpatched. Remove it first."
[ -e "$DOWNLOADS/$OPENCTM_FOLDER" ] && fail "$DOWNLOADS/$OPENCTM_FOLDER exists. MeshLab would build it unpatched. Remove it first."

apply_to_checkout "$VCGLIB" "$HRC/patches/vcglib"
apply_to_checkout "$MESHLAB" "$HRC/patches/meshlab"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$DOWNLOADS"

fetch "$WORK/$LIB3DS_ARCHIVE" "$LIB3DS_SHA256" "${LIB3DS_URLS[@]}"
tar -xzf "$WORK/$LIB3DS_ARCHIVE" -C "$DOWNLOADS" "$LIB3DS_FOLDER"
apply_to_archive "$DOWNLOADS/$LIB3DS_FOLDER" "$HRC/patches/lib3ds"

# OpenCTM's sources have Windows line endings. The patches are written against them with Unix ones.
fetch "$WORK/$OPENCTM_ARCHIVE" "$OPENCTM_SHA256" "${OPENCTM_URLS[@]}"
tar -xjf "$WORK/$OPENCTM_ARCHIVE" -C "$DOWNLOADS" "$OPENCTM_FOLDER"
find "$DOWNLOADS/$OPENCTM_FOLDER/lib" -type f \( -name '*.c' -o -name '*.h' \) -exec sed -i 's/\r$//' {} +
apply_to_archive "$DOWNLOADS/$OPENCTM_FOLDER" "$HRC/patches/openctm"

# Every file a patch touched is byte for byte the one that was tested.
(cd "$ROOT" && sha256sum --check --quiet "$HRC/patched.sha256") || fail "a patched file differs from patched.sha256."

# The package says which build it is, & the wheel carries the file, because the wheel keeps upstream's version.
{
  echo "HRConvert2's build $(cat "$HRC/BUILD_NUMBER") of PyMeshLab $(cat "$ROOT/PYML_VERSION")."
  echo "Patches applied, in order:"
  (cd "$HRC/patches" && printf '%s\n' vcglib/*.patch meshlab/*.patch lib3ds/*.patch openctm/*.patch)
} > "$ROOT/pymeshlab/HRCONVERT2_BUILD.txt"

date -u +%Y-%m-%dT%H:%M:%SZ > "$MARKER"
echo "Every patch is applied, & every patched file matches patched.sha256."
