#!/usr/bin/env bash
set -Eeuo pipefail
SRC="${1:?DualWeb source directory required}"
IBDIR="${2:?ImageBuilder directory required}"
WORK="${3:?Work directory required}"
OVERLAY="$SRC/overlay"
PACKAGES="$IBDIR/packages"
mkdir -p "$PACKAGES" "$OVERLAY/etc/openclash/core" "$OVERLAY/etc/dualweb"
download() { local url="$1" out="$2"; [[ -s "$out" ]] || curl --http1.1 -fL --retry 5 --retry-all-errors --retry-delay 3 --connect-timeout 30 "$url" -o "$out"; }

echo "========== Integrate ARM64 OpenClash =========="
OC_VERSION="v0.48.002"; OC_APK="luci-app-openclash-0.48.002.apk"
OC_URL="https://github.com/vernesong/OpenClash/releases/download/${OC_VERSION}/${OC_APK}"
OC_SHA="f7ebbd43f9be15c5e6df26e5d0c03d50d0bb8f7fa4cc0d2c2bf048b08c0b155b"
download "$OC_URL" "$WORK/$OC_APK"
printf '%s  %s\n' "$OC_SHA" "$WORK/$OC_APK" | sha256sum -c -
cp -f "$WORK/$OC_APK" "$PACKAGES/$OC_APK"
echo "Resolving latest stable Mihomo release for linux/arm64 ..."
MIHOMO_RELEASE_JSON="$WORK/mihomo-release.json"
download "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest" "$MIHOMO_RELEASE_JSON"
MIHOMO_VERSION="$(jq -r '.tag_name // empty' "$MIHOMO_RELEASE_JSON")"
[[ -n "$MIHOMO_VERSION" ]] || { echo "ERROR: Cannot resolve latest Mihomo release tag." >&2; exit 1; }
MIHOMO_ARCHIVE="$(jq -r --arg tag "$MIHOMO_VERSION" '.assets[].name | select(. == ("mihomo-linux-arm64-" + $tag + ".gz"))' "$MIHOMO_RELEASE_JSON" | head -n1)"
[[ -n "$MIHOMO_ARCHIVE" ]] || { echo "ERROR: Latest Mihomo release has no linux/arm64 gzip asset: $MIHOMO_VERSION" >&2; exit 1; }
download "https://github.com/MetaCubeX/mihomo/releases/download/${MIHOMO_VERSION}/${MIHOMO_ARCHIVE}" "$WORK/$MIHOMO_ARCHIVE"
gzip -t "$WORK/$MIHOMO_ARCHIVE"
gzip -dc "$WORK/$MIHOMO_ARCHIVE" > "$OVERLAY/etc/openclash/core/clash_meta"
chmod 0755 "$OVERLAY/etc/openclash/core/clash_meta"
file "$OVERLAY/etc/openclash/core/clash_meta"
readelf -h "$OVERLAY/etc/openclash/core/clash_meta" | grep -Eq 'Machine:.*AArch64' || { echo "ERROR: Mihomo core is not AArch64." >&2; exit 1; }

echo "========== Integrate Vantage theme =========="
VANTAGE_VERSION="v1.0.9"
VANTAGE_BASE="https://github.com/anothaDev/luci-theme-vantage/releases/download/${VANTAGE_VERSION}"
VANTAGE_OK=1
while IFS='|' read -r asset expected_sha; do
  [[ -n "$asset" ]] || continue
  dest="$PACKAGES/$asset"
  if download "$VANTAGE_BASE/$asset" "$dest" && printf '%s  %s\n' "$expected_sha" "$dest" | sha256sum -c -; then
    echo "Vantage package verified: $asset"
  else VANTAGE_OK=0; break; fi
done <<'VANTAGE_ASSETS'
luci-theme-vantage-1.0.9-r1.apk|d70ab2b4479b78bcf7e45ad70ddb251f4b57a66f711a7d58fae74c8ed8bff686
luci-app-vantage-1.0.9-r1.apk|b14853cc2f66b55982d63a14b6238552edfec6bdd4cbbf8278594be85ecd22e8
luci-i18n-vantage-zh-cn-1.0.9-r1.apk|cd1453cfd65e1a8fd4cb75023b0937cca4392f2077d88690a513da88834f6c07
VANTAGE_ASSETS
[[ "$VANTAGE_OK" == 1 ]] || { echo "ERROR: Vantage download/checksum failed." >&2; exit 1; }
touch "$OVERLAY/etc/dualweb/.vantage-installed"
chmod 0644 "$OVERLAY/etc/dualweb/.vantage-installed"

echo "========== Integrate ARM64 Open-Box runtime =========="
OPENBOX_VERSION="${OPENBOX_VERSION:-v0.1.341}"
OPENBOX_ARCHIVE="open-box-linux-arm64.tar.gz"
OPENBOX_BASE="https://github.com/liandu2024/Open-Box/releases/download/${OPENBOX_VERSION}"
download "${OPENBOX_BASE}/${OPENBOX_ARCHIVE}" "$WORK/$OPENBOX_ARCHIVE"
download "${OPENBOX_BASE}/${OPENBOX_ARCHIVE}.sha256" "$WORK/${OPENBOX_ARCHIVE}.sha256"
(cd "$WORK" && sha256sum -c "${OPENBOX_ARCHIVE}.sha256")
tar -tzf "$WORK/$OPENBOX_ARCHIVE" >/dev/null
OPENBOX_ROOT="$OVERLAY/opt/open-box"
rm -rf "$OPENBOX_ROOT"; mkdir -p "$OPENBOX_ROOT"
tar -xzf "$WORK/$OPENBOX_ARCHIVE" -C "$OPENBOX_ROOT"
test -s "$OPENBOX_ROOT/meta.json"
test -s "$OPENBOX_ROOT/openwrt/initd/openbox-panel"
test -s "$OPENBOX_ROOT/openwrt/initd/openbox"
mkdir -p "$OVERLAY/etc/init.d" "$OVERLAY/etc/uci-defaults" "$OVERLAY/usr/bin" "$OVERLAY/www/luci-static/resources/view/openbox" "$OVERLAY/usr/share/luci/menu.d" "$OVERLAY/usr/share/rpcd/acl.d"
cp "$OPENBOX_ROOT/openwrt/initd/openbox" "$OVERLAY/etc/init.d/openbox"
cp "$OPENBOX_ROOT/openwrt/initd/openbox-panel" "$OVERLAY/etc/init.d/openbox-panel"
chmod 0755 "$OVERLAY/etc/init.d/openbox" "$OVERLAY/etc/init.d/openbox-panel" "$OPENBOX_ROOT/openwrt/bin/open-box"
cp "$OPENBOX_ROOT/openwrt/luci/htdocs/luci-static/resources/view/openbox/"*.js "$OVERLAY/www/luci-static/resources/view/openbox/"
cp "$OPENBOX_ROOT/openwrt/luci/root/usr/share/luci/menu.d/luci-app-openbox.json" "$OVERLAY/usr/share/luci/menu.d/"
cp "$OPENBOX_ROOT/openwrt/luci/root/usr/share/rpcd/acl.d/luci-app-openbox.json" "$OVERLAY/usr/share/rpcd/acl.d/"
chmod 0644 "$OVERLAY/www/luci-static/resources/view/openbox/"*.js "$OVERLAY/usr/share/luci/menu.d/luci-app-openbox.json" "$OVERLAY/usr/share/rpcd/acl.d/luci-app-openbox.json"
ln -sfn /opt/open-box/openwrt/bin/open-box "$OVERLAY/usr/bin/open-box"
cat > "$OVERLAY/etc/uci-defaults/98-openbox" <<'OPENBOX_DEFAULTS'
#!/bin/sh
# Original Open-Box remains on 3036. Port 80 uses an isolated copied frontend.
mkdir -p /opt/open-box/data
[ -s /opt/open-box/data/panel-port ] || printf '3036\n' > /opt/open-box/data/panel-port
[ -s /opt/open-box/data/channel ] || printf 'direct\n' > /opt/open-box/data/channel
chmod 0755 /opt/open-box/openwrt/bin/open-box /etc/init.d/openbox /etc/init.d/openbox-panel
/etc/init.d/openbox disable >/dev/null 2>&1 || true
/etc/init.d/openbox-panel enable
/etc/init.d/openbox-panel start >/dev/null 2>&1 || true
rm -rf /tmp/luci-*cache* 2>/dev/null || true
exit 0
OPENBOX_DEFAULTS
chmod 0755 "$OVERLAY/etc/uci-defaults/98-openbox"

OPENBOX_WEB_INDEX="$(find "$OPENBOX_ROOT" -type f -name index.html -exec grep -l '<title>Open-Box</title>' {} + | head -n 1 || true)"
[[ -n "$OPENBOX_WEB_INDEX" ]] || { echo "ERROR: Open-Box index.html not found." >&2; exit 1; }
OPENBOX_WEB_ROOT="$(dirname "$OPENBOX_WEB_INDEX")"
OPENBOX_LITE_ROOT="$OVERLAY/www/dualweb/openbox-lite"
rm -rf "$OPENBOX_LITE_ROOT"; mkdir -p "$OPENBOX_LITE_ROOT"
cp -a "$OPENBOX_WEB_ROOT/." "$OPENBOX_LITE_ROOT/"
cp "$SRC/build-assets/openbox-lite-nav.js" "$OPENBOX_LITE_ROOT/dualweb-openbox-lite-nav.js"
cp "$SRC/build-assets/openbox-lite-nav.css" "$OPENBOX_LITE_ROOT/dualweb-openbox-lite-nav.css"
cp "$SRC/build-assets/openbox-lite-theme.css" "$OPENBOX_LITE_ROOT/dualweb-openbox-lite-theme.css"
python3 - "$OPENBOX_LITE_ROOT" <<'PYOPENBOXLITE'
from pathlib import Path
import re, sys
root = Path(sys.argv[1]); index = root / "index.html"
if not index.is_file(): raise SystemExit("ERROR: Open-Box lite frontend has no index.html")
for path in root.rglob("*"):
    if not path.is_file(): continue
    try: content = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError): continue
    updated = re.sub(r"(?<!/openbox-lite)/api/", "/openbox-lite/api/", content)
    updated = re.sub(r"(?<!/openbox-lite)/assets/", "/openbox-lite/assets/", updated)
    updated = re.sub(r"""(["'])\./openbox-lite/assets/""", r"\1/openbox-lite/assets/", updated)
    if path == index:
        if "</head>" not in updated or "</body>" not in updated: raise SystemExit("ERROR: Unexpected Open-Box index.html structure")
        updated = updated.replace("</head>", '<link rel="stylesheet" href="/openbox-lite/dualweb-openbox-lite-nav.css"><link rel="stylesheet" href="/openbox-lite/dualweb-openbox-lite-theme.css"></head>', 1)
        updated = updated.replace("</body>", '<script src="/openbox-lite/dualweb-openbox-lite-nav.js"></script></body>', 1)
    if updated != content: path.write_text(updated, encoding="utf-8")
PYOPENBOXLITE
test -s "$OPENBOX_LITE_ROOT/index.html"
grep -Fq '/openbox-lite/dualweb-openbox-lite-nav.css' "$OPENBOX_LITE_ROOT/index.html"
grep -Fq '/openbox-lite/dualweb-openbox-lite-theme.css' "$OPENBOX_LITE_ROOT/index.html"
grep -Fq '/openbox-lite/dualweb-openbox-lite-nav.js' "$OPENBOX_LITE_ROOT/index.html"
grep -Fq 'location ^~ /openbox-lite/api/' "$OVERLAY/etc/nginx/conf.d/dualweb.conf"
grep -Fq 'include /etc/dualweb/openbox-lite-backend.conf;' "$OVERLAY/etc/nginx/conf.d/dualweb.conf"
printf '%s\n' 'set $openbox_backend http://127.0.0.1:3036;' > "$OVERLAY/etc/dualweb/openbox-lite-backend.conf"
printf '3036\n' > "$OVERLAY/etc/dualweb/openbox-lite-backend-port"

echo "========== Integrate Zashboard on port 80 =========="
ZASHBOARD_URL="${ZASHBOARD_URL:-https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip}"
ZASHBOARD_ZIP="$WORK/zashboard-dist.zip"; ZASHBOARD_DIR="$WORK/zashboard-dist"
download "$ZASHBOARD_URL" "$ZASHBOARD_ZIP"
unzip -tq "$ZASHBOARD_ZIP"
rm -rf "$ZASHBOARD_DIR" "$OVERLAY/www/dualweb/zashboard"
mkdir -p "$ZASHBOARD_DIR" "$OVERLAY/www/dualweb/zashboard"
unzip -q "$ZASHBOARD_ZIP" -d "$ZASHBOARD_DIR"
ZASHBOARD_INDEX="$(find "$ZASHBOARD_DIR" -type f -name index.html -print -quit)"
[[ -n "$ZASHBOARD_INDEX" ]] || { echo "ERROR: Zashboard archive has no index.html" >&2; exit 1; }
cp -a "$(dirname "$ZASHBOARD_INDEX")/." "$OVERLAY/www/dualweb/zashboard/"
test -s "$OVERLAY/www/dualweb/zashboard/index.html"

for f in "$OVERLAY/etc/nginx/conf.d/dualweb.conf" "$OVERLAY/etc/dualweb/openbox-lite-backend.conf" "$OVERLAY/etc/dualweb/openbox-lite-backend-port" "$OVERLAY/www/dualweb/index.html" "$OVERLAY/www/dualweb/app.js" "$OVERLAY/www/dualweb/openbox-lite/index.html" "$OVERLAY/www/dualweb/zashboard/index.html" "$OVERLAY/etc/init.d/openbox-panel" "$OVERLAY/etc/init.d/openbox"; do
  test -s "$f" || { echo "ERROR: Missing required integration file: $f" >&2; exit 1; }
done
echo "ARM64 OpenClash, Vantage, Open-Box lite and Zashboard assets staged."
