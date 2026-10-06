#!/bin/sh
# Installs netbird-bridge on a GL.iNet router and sets it up in one go:
#
#   wget -qO- https://raw.githubusercontent.com/SerhiyGreench/glinet-netbird-bridge/main/install.sh \
#     | sh -s -- --setup-key <KEY> [--management-url <URL>]
#
# Every option after `--` is passed to `netbird-bridge setup`. Put --release vX.Y.Z
# first to install a particular release instead of the latest.
set -e

REPO=SerhiyGreench/glinet-netbird-bridge

die() { printf 'install: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "run this as root on the router"
[ -f /etc/openwrt_release ] || die "this is not an OpenWrt/GL.iNet router"

release=latest
if [ "$1" = --release ]; then
	release="$2"
	shift 2
fi

if [ "$release" = latest ]; then
	url="https://github.com/$REPO/releases/latest/download/netbird-bridge.ipk"
else
	url="https://github.com/$REPO/releases/download/$release/netbird-bridge.ipk"
fi

ipk=/tmp/netbird-bridge.ipk
echo "Downloading netbird-bridge ($release)…"
if command -v curl >/dev/null 2>&1; then
	curl -fsSL -o "$ipk" "$url" || die "download failed: $url"
else
	wget -qO "$ipk" "$url" || die "download failed: $url"
fi

if ! opkg install --force-reinstall "$ipk" >/tmp/netbird-bridge-opkg.log 2>&1; then
	echo "Fetching dependencies…"
	opkg update >/dev/null 2>&1 || true
	opkg install --force-reinstall "$ipk" || { rm -f "$ipk"; die "opkg could not install the package"; }
fi
rm -f "$ipk" /tmp/netbird-bridge-opkg.log

exec /usr/sbin/netbird-bridge setup "$@"
