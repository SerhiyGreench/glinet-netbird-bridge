#!/bin/sh
# Builds dist/netbird-bridge_<version>_all.ipk in the layout OpenWrt's ipkg-build writes.
set -eu

cd "$(dirname "$0")/.."
VERSION="${1:-$(git describe --tags --always --dirty 2>/dev/null | sed 's/^v//')}"
VERSION="${VERSION:-0.0.0}"
OUT=dist
PKG="$OUT/netbird-bridge_${VERSION}_all.ipk"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/data" "$tmp/control" "$OUT"

cp -a files/. "$tmp/data/"
sed -i "s/@VERSION@/$VERSION/" "$tmp/data/usr/sbin/netbird-bridge"
chmod 755 "$tmp/data/usr/sbin/netbird-bridge" "$tmp/data/etc/init.d/netbird-bridge"
chmod 644 "$tmp/data/etc/config/netbird-bridge"

size="$(du -sb "$tmp/data" | cut -f1)"
sed -e "s/@VERSION@/$VERSION/" -e "s/@SIZE@/$size/" package/control > "$tmp/control/control"
cp package/conffiles package/postinst package/prerm "$tmp/control/"
chmod 755 "$tmp/control/postinst" "$tmp/control/prerm"

TAR="tar --format=gnu --numeric-owner --owner=0 --group=0 --sort=name --mtime=@0"
(cd "$tmp/data" && $TAR -czf ../data.tar.gz .)
(cd "$tmp/control" && $TAR -czf ../control.tar.gz .)
echo "2.0" > "$tmp/debian-binary"
(cd "$tmp" && $TAR -czf pkg.ipk ./debian-binary ./data.tar.gz ./control.tar.gz)
mv "$tmp/pkg.ipk" "$PKG"
echo "$PKG"
