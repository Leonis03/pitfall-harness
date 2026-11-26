# linux-desktop/fedora/files/bashrc.d/50-proxy.sh
#
# Deploy to: ~/.bashrc.d/50-proxy.sh
# Loaded by the hook this machine's ~/.bashrc already has ("if [ -d ~/.bashrc.d ]").
#
# Proxy auto-detection for the local Clash-family client (FlClash / Clash Verge).
#
# Source of truth: shell/files/shell_common, section 5
#   ("a listening port is not a proxy -- ask it what it speaks", commit 9b205c5).
#   The probe below is copied verbatim from that file; edit it there, then mirror
#   the change here. This copy is bash-only. It clears the variables the
#   session environment hands down above its section 5; the shared file does
#   the same inside its section 5 since 2026-11-21.
#
# Why this exists: the client is switchable. A hardcoded port in ~/.bashrc
# points every CLI request at a dead port the moment the client is turned off,
# while a direct connection works fine -- that is the "the terminal has no
# network" failure. Here the candidate ports are HANDSHAKEN (SOCKS5:
# 05 01 00 -> 05 00; HTTP: CONNECT -> 200 Connection established) and only a
# port that actually answers as a proxy gets exported. If nothing answers, NO
# proxy variable is exported at all and the direct path is used.
#
# This machine: native Fedora 44, the client listens on the same host, so the
# proxy host is the loopback. (On WSL under NAT it would have to be derived
# from the default route -- see the comment in the copied section.)

# START FROM A CLEAN SLATE.
# The desktop session carries its own proxy variables (systemctl --user
# show-environment) that the client injected while it was running; a shell
# started from the desktop inherits them. When the client is later stopped
# those inherited values point at a dead port again, so clearing them is what
# actually makes the direct path available. They are re-exported below only if
# the probe finds a port that really answers as a proxy.
unset http_proxy https_proxy all_proxy
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY

# 5. Proxy (Clash-family client on the host: Clash Verge Rev, Clash, FlClash ...)
#
# host_ip=127.0.0.1 is only correct because the VM runs with
# networkingMode=mirrored, set in %USERPROFILE%\.wslconfig (files/wslconfig).
# Mirrored networking makes the Windows loopback and the WSL loopback the same
# address. Under the default NAT mode the host is somewhere else entirely and
# 127.0.0.1 points back at WSL, so every proxied request fails with connection
# refused -- with nothing here to suggest the cause is a file on the Windows
# side. If you are on NAT, derive the host from the default route instead:
#   host_ip=$(ip route show default | awk '/default/ {print $3}')
# An existing host_ip in the environment wins over the default below.
#
# FOUR THINGS THAT DO NOT PORT TO ANOTHER ENVIRONMENT:
#
# 1. THE PORT IS DETECTED, NOT ASSUMED. The mixed port differs per client
#    (Clash Verge Rev 7897, Clash 7890) and this file is deployed to several
#    machines, so a list of the common ports is probed instead of one
#    hardcoded number. To skip the list, export PROXY_PORT (one mixed port)
#    or PROXY_HTTP_PORT plus PROXY_SOCKS_PORT (two separate ports) before
#    this file is sourced. An explicit value is probed too, so one that points
#    at a closed port is dropped rather than exported.
#
# 2. A LISTENING PORT IS NOT A PROXY. Port 8080 can be a web server. Each
#    candidate is handshaked -- SOCKS5 (05 01 00 -> 05 00) and HTTP (CONNECT
#    -> 200 Connection established) -- and a port that answers neither is not
#    a proxy and is dropped. That is what keeps a dev server on 8080 from
#    becoming http_proxy.
#
# 3. ONE PORT PER VARIABLE. A MIXED port speaks HTTP and SOCKS5 on the same
#    socket. A client that listens on two separate ports needs two values:
#    ALL_PROXY pointed at the HTTP port fails with "Connection reset by
#    peer", because that port only answers HTTP CONNECT. Test which is which
#    before assuming:
#      curl -x http://127.0.0.1:<p>      <url>   # HTTP?
#      curl -x socks5h://127.0.0.1:<p>   <url>   # SOCKS5?
#    The two variables are kept apart even when they happen to be equal.
#
# 4. THE PROXY MAY VANISH -- OR MAY HAVE NO PORT AT ALL. A switchable app (an
#    Android proxy app, a container that gets stopped) leaves a dead port
#    behind; a client in TUN mode opens NO local port, because it takes the
#    traffic at the network layer and the application connects or not. Export
#    variables that point at a port nothing listens on and every proxied
#    request is refused -- while a direct connection works fine. That is the
#    "the terminal has no network" failure. So: probe first, export only if a
#    port answers, and keep NO_PROXY either way.
#      timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/<port>' && echo OPEN || echo refused
#    (/dev/tcp is bash-only; call bash explicitly under zsh.)
#    Background: agent/skills/android-chroot-debian/references/proxy-and-socket-pitfalls.md
# ------------------------------------------------------------------------------
export host_ip="${host_ip:-127.0.0.1}"

# Probe the candidate ports and report which proxy protocol each one speaks.
# One bash does the whole scan -- /dev/tcp for the connect and bash read for
# the reply -- so the cost is one process spawn, not one per port. zsh has no
# /dev/tcp, which is why the probe runs under bash.
# Prints "http=PORT;socks=PORT"; an empty field means "no port for that
# protocol". The scanner does the picking as well: the caller must not split
# the answer on whitespace, because zsh does not word-split an unquoted
# expansion and would hand the whole list to the probe as one argument.
_proxy_scan() {
    bash -s -- "$host_ip" "$@" <<'_PROXY_SCAN'
host="$1"; shift
probe_socks() {
    local r=""
    exec 3<>"/dev/tcp/${host}/$1" 2>/dev/null || return 1
    printf '\x05\x01\x00' >&3 2>/dev/null || { exec 3<&-; return 1; }
    IFS= read -r -N 1 -t 1 -u 3 r 2>/dev/null
    exec 3<&- 2>/dev/null
    [ "$r" = $'\x05' ]
}
probe_http() {
    local r=""
    exec 3<>"/dev/tcp/${host}/$1" 2>/dev/null || return 1
    printf 'CONNECT 127.0.0.1:1 HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n' >&3 2>/dev/null || { exec 3<&-; return 1; }
    IFS= read -r -t 1 -u 3 r 2>/dev/null
    exec 3<&- 2>/dev/null
    r="${r%$'\r'}"
    case "$r" in
        "HTTP/1."*200*|"HTTP/1."*403*|"HTTP/1."*502*|"HTTP/1."*503*) return 0 ;;
    esac
    return 1
}
# Where to look. A hint about where, not a claim about what is there: every
# candidate is handshaked and a port that does not answer as a proxy is
# dropped. 7897 = Clash Verge Rev mixed, 7890 = Clash/Mihomo mixed or HTTP,
# 7891 = Clash socks, 8080/8888/3128/8118 = the usual HTTP-proxy ports,
# 1080/10808 = the usual SOCKS ports, 10809 = v2rayN HTTP.
# Deliberately absent: 7892 and 7893 (Clash redir/tproxy), which are
# transparent ports and answer neither CONNECT nor a SOCKS5 greeting.
ports="$*"
if [ -z "$ports" ]; then
    ports="7897 7890 7891 8080 8888 3128 8118 1080 10808 10809"
fi
mixed=""; http=""; socks=""
for p in $ports; do
    s=0; h=0
    probe_socks "$p" && s=1
    probe_http  "$p" && h=1
    if [ "$s" = 1 ] && [ "$h" = 1 ]; then
        mixed="$p"
        break
    elif [ "$s" = 1 ]; then
        [ -n "$socks" ] || socks="$p"
    elif [ "$h" = 1 ]; then
        [ -n "$http" ] || http="$p"
    fi
done
# A mixed port is the client's own port and serves both protocols, so it wins
# outright; otherwise each variable gets the port that speaks its protocol.
if [ -n "$mixed" ]; then
    http="$mixed"
    socks="$mixed"
fi
printf 'http=%s;socks=%s\n' "$http" "$socks"
_PROXY_SCAN
}

# An explicit configuration replaces the candidate list -- but is still
# probed, so a value that points at a closed port, or at something that is
# not a proxy at all, is dropped rather than exported.
if [ -n "${PROXY_HTTP_PORT:-}" ] || [ -n "${PROXY_SOCKS_PORT:-}" ]; then
    _proxy_line="$(_proxy_scan "$PROXY_HTTP_PORT" "$PROXY_SOCKS_PORT" 2>/dev/null)"
elif [ -n "${PROXY_PORT:-}" ]; then
    _proxy_line="$(_proxy_scan "$PROXY_PORT" 2>/dev/null)"
else
    _proxy_line="$(_proxy_scan 2>/dev/null)"
fi

# Cut the answer apart with parameter expansion, not with word splitting:
# zsh does not split an unquoted expansion, so a `for x in $line` loop would
# see one word there and the probe would never find a port.
_proxy_http="${_proxy_line#http=}";  _proxy_http="${_proxy_http%%;*}"
_proxy_socks="${_proxy_line##*socks=}"

if [ -n "$_proxy_http" ]; then
    # proxy_port stays for anything that still reads the old single value;
    # the two specific variables are the authoritative ones.
    export proxy_port="$_proxy_http"
    export proxy_http_port="$_proxy_http"

    export HTTP_PROXY="http://${host_ip}:${_proxy_http}"
    export HTTPS_PROXY="http://${host_ip}:${_proxy_http}"
    export http_proxy="http://${host_ip}:${_proxy_http}"
    export https_proxy="http://${host_ip}:${_proxy_http}"
fi

if [ -n "$_proxy_socks" ]; then
    export proxy_socks_port="$_proxy_socks"

    export ALL_PROXY="socks5h://${host_ip}:${_proxy_socks}"
    export all_proxy="socks5h://${host_ip}:${_proxy_socks}"
fi

if [ -z "$_proxy_http" ] && [ -z "$_proxy_socks" ]; then
    # Nothing speaks a proxy protocol: the client is off, or it is in TUN
    # mode and opens no port. Export no proxy variables at all -- the direct
    # connection is the path that works. NO_PROXY below stays either way.
    unset proxy_port proxy_http_port proxy_socks_port
fi
unset -f _proxy_scan 2>/dev/null
unset _proxy_line _proxy_http _proxy_socks

# NO_PROXY is exported either way -- with or without a proxy in use.
# Host names are written out in full on purpose: a bare "*" is special-cased,
# but a prefixed wildcard such as "*.local" or "127.*" is NOT, and it silently
# sends local traffic through the proxy (502 with an empty body -- see
# tools/python/ section 1 in the same repository).
export no_proxy="localhost,127.0.0.1,::1,.local"
export NO_PROXY="$no_proxy"
