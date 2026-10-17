#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
RELEASE="${RELEASE:-25.12-SNAPSHOT}"
TARGET="qualcommax/ipq60xx"
PROFILE="jdcloud_re-ss-01"
BASE="https://downloads.immortalwrt.org/releases/${RELEASE}/targets/${TARGET}"
WORK="${ROOT}/work"
OUT="${ROOT}/output"
DUALWEB_REPO="${DUALWEB_REPO:-https://github.com/wfzc6880530/dualweb.git}"
DUALWEB_REF="${DUALWEB_REF:-test/openbox-artifacts}"

mkdir -p "$WORK" "$OUT"
IB="immortalwrt-imagebuilder-${RELEASE}-qualcommax-ipq60xx.Linux-x86_64.tar.zst"
URL="${BASE}/${IB}"

if [[ ! -s "$WORK/$IB" ]]; then
  echo "Downloading ImageBuilder: $URL"
  curl -fL --retry 4 --retry-delay 3 --connect-timeout 30 "$URL" -o "$WORK/$IB"
fi

curl -fsSL "${BASE}/sha256sums" -o "$WORK/sha256sums"
EXPECTED="$(grep -F "$IB" "$WORK/sha256sums" | head -n1 | awk '{print $1}')"
if [[ -z "$EXPECTED" ]]; then
  echo "ERROR: official checksum entry not found for $IB" >&2
  exit 1
fi
ACTUAL="$(sha256sum "$WORK/$IB" | awk '{print $1}')"
if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  echo "ERROR: ImageBuilder SHA256 mismatch" >&2
  echo "expected: $EXPECTED" >&2
  echo "actual:   $ACTUAL" >&2
  exit 1
fi
echo "ImageBuilder SHA256 verified: $ACTUAL"

rm -rf "$WORK/imagebuilder" "$WORK/dualweb"
mkdir -p "$WORK/imagebuilder"
tar --zstd -xf "$WORK/$IB" -C "$WORK/imagebuilder" --strip-components=1
IBDIR="$WORK/imagebuilder"

echo "========== Confirm device profile =========="
if ! grep -Rqs "$PROFILE" "$IBDIR/target/linux" "$IBDIR/profiles.json" "$IBDIR"; then
  echo "ERROR: ImageBuilder does not expose profile $PROFILE for $TARGET." >&2
  exit 1
fi

echo "========== Get DualWeb source =========="
git clone --depth 1 --branch "$DUALWEB_REF" "$DUALWEB_REPO" "$WORK/dualweb"
test -s "$WORK/dualweb/src/main.go"
test -d "$WORK/dualweb/overlay/www/dualweb"

echo "========== Build ARM64 DualWeb API =========="
if ! command -v go >/dev/null 2>&1; then
  echo "ERROR: Go compiler not installed." >&2
  exit 1
fi
mkdir -p "$WORK/dualweb/overlay/usr/sbin"
(
  cd "$WORK/dualweb"
  CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -ldflags='-s -w' \
    -o overlay/usr/sbin/dualweb-api src/main.go
)
chmod 0755 "$WORK/dualweb/overlay/usr/sbin/dualweb-api"

# Copy the portable DualWeb overlay. Do not copy the x86 packages.txt.
mkdir -p "$IBDIR/files" "$IBDIR/packages"
cp -a "$WORK/dualweb/overlay/." "$IBDIR/files/"
chmod 0755 "$IBDIR/files/etc/uci-defaults/99-dualweb"
chmod 0755 "$IBDIR/files/etc/init.d/dualweb-api"
chmod 0755 "$IBDIR/files/etc/init.d/dualweb-firstboot"
chmod 0755 "$IBDIR/files/usr/sbin/dualweb-firstboot-packages"
chmod 0755 "$IBDIR/files/usr/sbin/dualweb-api"

PACKAGES="$(grep -vE '^[[:space:]]*(#|$)' "$ROOT/packages.txt" | xargs)"
echo "========== Validate package manifest =========="
make -C "$IBDIR" manifest PROFILE="$PROFILE" PACKAGES="$PACKAGES"

echo "========== Build JDCloud firmware =========="
make -C "$IBDIR" image PROFILE="$PROFILE" PACKAGES="$PACKAGES" FILES="$IBDIR/files" BIN_DIR="$OUT"

echo "========== Validate firmware outputs =========="
INITRAMFS="$(find "$OUT" -maxdepth 1 -type f -name '*jdcloud_re-ss-01-initramfs-uImage.itb' -print -quit)"
SYSUPGRADE="$(find "$OUT" -maxdepth 1 -type f -name '*jdcloud_re-ss-01-squashfs-sysupgrade.bin' -print -quit)"
if [[ -z "$INITRAMFS" || ! -s "$INITRAMFS" ]]; then
  echo "ERROR: missing JDCloud initramfs image; inspect ImageBuilder output." >&2
  find "$OUT" -maxdepth 1 -type f -printf '%f (%s bytes)\n' >&2
  exit 1
fi
if [[ -z "$SYSUPGRADE" || ! -s "$SYSUPGRADE" ]]; then
  echo "ERROR: missing JDCloud sysupgrade image; inspect ImageBuilder output." >&2
  find "$OUT" -maxdepth 1 -type f -printf '%f (%s bytes)\n' >&2
  exit 1
fi

# Retain only the two device-specific images plus metadata/checksums.
find "$OUT" -maxdepth 1 -type f \
  ! -name '*jdcloud_re-ss-01-initramfs-uImage.itb' \
  ! -name '*jdcloud_re-ss-01-squashfs-sysupgrade.bin' \
  ! -name 'profiles.json' ! -name 'version.buildinfo' ! -name '*.manifest' \
  ! -name 'sha256sums' -delete

cp -f "$IBDIR/profiles.json" "$OUT/profiles.json" 2>/dev/null || true
cp -f "$IBDIR/target/linux/qualcommax/ipq60xx/version.buildinfo" "$OUT/version.buildinfo" 2>/dev/null || true
(
  cd "$OUT"
  sha256sum * > SHA256SUMS.txt
)
echo "Build complete:"
find "$OUT" -maxdepth 1 -type f -printf '%f (%s bytes)\n'
