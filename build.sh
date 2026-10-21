#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
RELEASE="${RELEASE:-25.12.2}"
TARGET="qualcommax/ipq60xx"
PROFILE="jdcloud_re-ss-01"
if [[ "$RELEASE" == "SNAPSHOT" ]]; then
  BASE="https://downloads.immortalwrt.org/snapshots/targets/${TARGET}"
  IB="immortalwrt-imagebuilder-qualcommax-ipq60xx.Linux-x86_64.tar.zst"
else
  BASE="https://downloads.immortalwrt.org/releases/${RELEASE}/targets/${TARGET}"
  IB="immortalwrt-imagebuilder-${RELEASE}-qualcommax-ipq60xx.Linux-x86_64.tar.zst"
fi
WORK="${ROOT}/work"
OUT="${ROOT}/output"
DUALWEB_REPO="${DUALWEB_REPO:-https://github.com/wfzc6880530/dualweb.git}"
DUALWEB_REF="${DUALWEB_REF:-test/2026-10-21-functional-b-scheme}"

mkdir -p "$WORK" "$OUT"
rm -f "$OUT"/*
URL="${BASE}/${IB}"

if [[ ! -s "$WORK/$IB" ]]; then
  echo "Downloading OpenWrt ImageBuilder: $URL"
  curl --http1.1 -fL --retry 6 --retry-all-errors --retry-delay 3 --connect-timeout 30 "$URL" -o "$WORK/$IB"
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

echo "========== ImageBuilder profile validation will run via make manifest =========="
echo "========== Get DualWeb source =========="
git clone --depth 1 --branch "$DUALWEB_REF" "$DUALWEB_REPO" "$WORK/dualweb"
test -s "$WORK/dualweb/src/main.go"
test -d "$WORK/dualweb/overlay/www/dualweb"

echo "========== Integrate plugins and port-80 panels =========="
bash "$ROOT/integrate-arm64.sh" "$WORK/dualweb" "$IBDIR" "$WORK"

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

# The upstream ImageBuilder profile currently emits sysupgrade, not initramfs.
# Treat initramfs as optional; a valid sysupgrade image is the required artifact.
if [[ -z "$SYSUPGRADE" || ! -s "$SYSUPGRADE" ]]; then
  echo "ERROR: missing JDCloud sysupgrade image; inspect ImageBuilder output." >&2
  find "$OUT" -maxdepth 1 -type f -printf '%f (%s bytes)\n' >&2
  exit 1
fi
if [[ -n "$INITRAMFS" && -s "$INITRAMFS" ]]; then
  echo "Optional initramfs image found: $INITRAMFS"
else
  echo "NOTE: ImageBuilder did not produce an initramfs image for this profile; sysupgrade image is present."
fi

# Retain the device sysupgrade image, optional initramfs, and useful metadata.
find "$OUT" -maxdepth 1 -type f \
  ! -name '*jdcloud_re-ss-01-initramfs-uImage.itb' \
  ! -name '*jdcloud_re-ss-01-squashfs-sysupgrade.bin' \
  ! -name 'profiles.json' ! -name 'version.buildinfo' ! -name '*.manifest' \
  ! -name '*.bom.cdx.json' ! -name 'sha256sums' -delete


cp -f "$IBDIR/profiles.json" "$OUT/profiles.json" 2>/dev/null || true
cp -f "$IBDIR/target/linux/qualcommax/ipq60xx/version.buildinfo" "$OUT/version.buildinfo" 2>/dev/null || true
(
  cd "$OUT"
  find . -maxdepth 1 -type f ! -name 'SHA256SUMS.txt' -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS.txt
)
echo "Build complete:"
find "$OUT" -maxdepth 1 -type f -printf '%f (%s bytes)\n'
