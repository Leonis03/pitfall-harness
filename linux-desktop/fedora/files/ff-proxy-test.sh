#!/usr/bin/env bash
# linux-desktop/fedora/files/ff-proxy-test.sh
#
# Read-only probe. Not deployed; copy it anywhere and run it.
#
# Loads a URL in headless Firefox with every proxy environment variable
# stripped, so the only possible proxy source left is the GNOME gsettings
# schema (org.gnome.system.proxy.*). That is the path Firefox actually uses
# on this machine -- it has no KDE (kioslaverc) support.
#
# Use a URL that is blocked without a proxy; a page that renders proves the
# GNOME schema is working, no page means it is not.
#
# usage: ff-proxy-test.sh <profile-dir> <png-out> <url>
#   ./ff-proxy-test.sh /tmp/ffprof /tmp/ff.png https://www.google.com/
#
# To A/B the GNOME schema:
#   gsettings set org.gnome.system.proxy mode manual   -> expect a page
#   gsettings set org.gnome.system.proxy mode none      -> expect no page
#
# Note: "gsettings set org.gnome.system.proxy.http enabled false" does NOT
# change the outcome -- libxul ignores that key. See README.md section 4.1.

set -u

prof=${1:?profile dir}
out=${2:?png output}
url=${3:?url}

rm -rf "$prof" "$out"
mkdir -p "$prof"

exec env -u http_proxy -u https_proxy -u all_proxy \
        -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
        -u no_proxy -u NO_PROXY \
    timeout 90 firefox --headless --no-remote --profile "$prof" \
    --screenshot "$out" --window-size=1000,800 "$url" >/dev/null 2>&1
