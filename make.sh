#!/usr/bin/env bash
# make.sh [name]: one-stop profile maker. Asks for the server config exported from RustDesk,
# Tailscale mode, the RustDesk password and an unlock passphrase; writes profiles/<name>.conf
# (secrets encrypted) and builds dist/<name>/ installers. Run it yourself: it prompts for secrets.
set -euo pipefail
# The tool (templates, guides) lives next to this script; profiles/, brand-src/ and dist/ live in RD_ROOT
# (a private repo that keeps the tool in tool/), or next to the script when RD_ROOT is unset.
tool=$(cd "$(dirname "$0")" && pwd)
export RD_ROOT=${RD_ROOT:-$tool}
cd "$RD_ROOT"

name=${1:-}
[ -n "$name" ] || read -rp "Profile name (e.g. home, work): " name
[[ "$name" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "name: letters, digits, - and _ only" >&2; exit 1; }
conf="profiles/$name.conf"
cur() { [ -f "$conf" ] && sed -n "s/^$1=//p" "$conf" | head -1 || true; }
ask() { local v; read -rp "$1 [$2]: " v; printf '%s' "${v:-$2}"; }
secret_twice() {
  local a b
  read -rsp "$1: " a; echo >&2
  read -rsp "$1 again: " b; echo >&2
  [ -n "$a" ] && [ "$a" = "$b" ] || { echo "empty or didn't match" >&2; exit 1; }
  printf '%s' "$a"
}

id=$(cur ID_SERVER); relay=$(cur RELAY_SERVER); key=$(cur KEY)
echo "Server: in RustDesk, Settings > Network > ID/Relay server > Export server config, then paste here."
read -rp "Paste config (Enter = keep current${id:+: $id}${id:-: public servers}; '-' = public servers): " cfg
if [ "$cfg" = - ]; then
  id= relay= key=
elif [ -n "$cfg" ]; then
  # RustDesk export = base64(JSON {host, relay, api, key}) written backwards.
  out=$(python3 -c '
import sys, json, base64, re
s = sys.argv[1].strip()[::-1]; s += "=" * (-len(s) % 4)
d = json.loads(base64.b64decode(s))
host, relay, key = (str(d.get(k, "")) for k in ("host", "relay", "key"))
# These land in the installers, so only plain host names / base64 are accepted.
assert all(re.fullmatch(r"[A-Za-z0-9.:\[\]-]*", v) for v in (host, relay)) and re.fullmatch(r"[A-Za-z0-9+/=]*", key)
print(host); print(relay); print(key)' "$cfg" 2>/dev/null) \
    || { echo "that doesn't look like a RustDesk exported server config" >&2; exit 1; }
  mapfile -t f <<<"$out"
  id=${f[0]}; relay=${f[1]}; key=${f[2]}
fi
echo "  ID server: ${id:-public}  relay: ${relay:-auto}  key: ${key:-none}"

# Suggest the newest stable RustDesk release (Enter takes it); fall back to the profile's version offline.
latest=$(curl -fsSL --max-time 10 https://api.github.com/repos/rustdesk/rustdesk/releases/latest 2>/dev/null |
  python3 -c 'import sys, json; t = json.load(sys.stdin)["tag_name"]; print(t if all(p.isdigit() for p in t.split(".")) else "")' 2>/dev/null || true)
now=$(cur VERSION)
if [ -n "$latest" ] && [ -n "$now" ] && [ "$latest" != "$now" ]; then
  echo "  This profile uses RustDesk $now; the newest is $latest."
fi
ver=$(ask "RustDesk version (Enter = newest)" "${latest:-${now:-1.5.0}}")
[[ "$ver" =~ ^[0-9.]+$ ]] || { echo "version: digits and dots only, e.g. 1.5.0" >&2; exit 1; }
ts=$(ask "Tailscale (login/key/none)" "$(cur TAILSCALE | grep . || echo none)")
case $ts in login|key|none) ;; *) echo "Tailscale must be login, key or none" >&2; exit 1;; esac
brands=$(cd brand-src 2>/dev/null && ls -d */ 2>/dev/null | tr -d / | tr '\n' / )
brand=$(ask "Brand (${brands}none)" "$(cur BRAND | grep . || echo none)")
[ "$brand" = none ] && brand=
[ -z "$brand" ] || [ -f "brand-src/$brand/brand.conf" ] || { echo "no brand-src/$brand/brand.conf" >&2; exit 1; }
helper=$(ask "Who people should contact (shown in the installer)" "$(cur HELPER | grep . || echo your support person)")

pw=$(secret_twice "RustDesk password")
tskey=
[ "$ts" != key ] || tskey=$(secret_twice "Tailscale auth key")
RD_UNLOCK=$(secret_twice "Unlock passphrase (typed at each install; 16+ characters, e.g. 4 random words)")
# The file may float around for years and can be attacked offline, so no short passphrases.
[ ${#RD_UNLOCK} -ge 16 ] || { echo "passphrase: 16+ characters please (e.g. 4 random words)" >&2; exit 1; }
export RD_UNLOCK
# "ok:" prefix lets the installer tell a wrong passphrase from a lucky-padding garbage decrypt.
seal() { [ -z "$1" ] || printf 'ok:%s' "$1" | openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -md sha256 -salt -a -A -pass env:RD_UNLOCK; }

cat > "$conf" <<EOF
# Made by make.sh $(date +%F). Rerun ./make.sh $name to change.
# Blank ID_SERVER = RustDesk public servers. TAILSCALE: login | key | none
ID_SERVER=$id
RELAY_SERVER=$relay
KEY=$key
VERSION=$ver
TAILSCALE=$ts
HELPER=$helper
BRAND=$brand
PASSWORD_ENC=$(seal "$pw")
TS_AUTHKEY_ENC=$(seal "$tskey")
EOF
unset RD_UNLOCK
echo "wrote $conf"
"$tool/build.sh" "$name"
