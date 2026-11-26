#!/usr/bin/env bash
# linux-desktop/fedora/files/chrome-proxy-test.sh
#
# Read-only probe. Not deployed; copy it anywhere and run it.
#
# Loads a URL in headless Chrome with every proxy environment variable
# stripped, so the only possible proxy source left is the desktop
# configuration -- ~/.config/kioslaverc on this machine. That is the path
# Chromium actually uses under KDE; it has no use for the GNOME schema.
#
# The judge is the exit IP, not the page title:
#   - https://ipinfo.io/ip answers with the caller's IP as plain text, and it
#     is reachable BOTH directly and through the proxy on this network.
#   - so the IP in the rendered DOM says which path the browser took.
#
# Three outcomes, all of them useful:
#   PROXIED  -- the DOM carries the proxy's exit IP
#   DIRECT   -- the DOM carries the direct exit IP
#   BROKEN   -- the DOM carries neither: the browser was pointed at a proxy
#               whose port answers nothing (the "kioslaverc still says
#               ProxyType=1 but the client is off" case)
#
# usage: chrome-proxy-test.sh [profile-dir]
#   ./chrome-proxy-test.sh /tmp/cprof
#
# To A/B the KDE desktop proxy:
#   sed -i 's/^ProxyType=0$/ProxyType=1/' ~/.config/kioslaverc -> expect PROXIED
#   sed -i 's/^ProxyType=1$/ProxyType=0/' ~/.config/kioslaverc -> expect DIRECT
#
# Note: a running Chrome has to be restarted to pick the change up; the probe
# starts its own instance with a throwaway profile, so it always reads the
# current file.

set -u

prof=${1:-/tmp/cprof-chrome-test}
probe_url="https://ipinfo.io/ip"

# Reference IPs, one per path. Taken with curl so the browser is compared
# against the same machine's own results.
proxy_ip=$(timeout 20 curl -sS "$probe_url" 2>/dev/null | tr -d '[:space:]')
direct_ip=$(timeout 20 curl -sS --noproxy '*' "$probe_url" 2>/dev/null | tr -d '[:space:]')

if [ -z "$proxy_ip" ] || [ -z "$direct_ip" ]; then
    echo "RESULT=INCONCLUSIVE (reference IPs unavailable: proxy='$proxy_ip' direct='$direct_ip')"
    exit 2
fi

rm -rf "$prof"
mkdir -p "$prof"

dom=$(env -u http_proxy -u https_proxy -u all_proxy \
         -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
         -u no_proxy -u NO_PROXY \
     timeout 60 google-chrome --headless=new --no-sandbox --disable-gpu \
         --disable-dev-shm-usage --user-data-dir="$prof" \
         --dump-dom "$probe_url" 2>/dev/null)

if printf '%s' "$dom" | grep -q "$proxy_ip"; then
    echo "RESULT=PROXIED (browser exited via the proxy, ip=$proxy_ip)"
elif printf '%s' "$dom" | grep -q "$direct_ip"; then
    echo "RESULT=DIRECT (browser exited directly, ip=$direct_ip)"
else
    echo "RESULT=BROKEN (neither ip in the DOM; expected proxy=$proxy_ip direct=$direct_ip; dom bytes=$(printf '%s' "$dom" | wc -c))"
    printf '%s' "$dom" | grep -o -m1 'ERR_[A-Z_]*'
fi
