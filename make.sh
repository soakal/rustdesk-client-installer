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
# Say plainly how it ended: a half-finished run must not look like success.
saved=
trap 'rc=$?; echo >&2; if [ $rc -eq 0 ]; then echo "==> DONE. Installers are in $RD_ROOT/dist/$name/" >&2
  elif [ -n "$saved" ]; then echo "*** NOT FINISHED - your answers are saved in $conf but the installers in dist/$name/ are not complete. Fix the problem above and run ./build.sh $name (no questions). ***" >&2
  else echo "*** NOT FINISHED - nothing was saved or built. Fix the problem above and run ./make.sh $name again. ***" >&2; fi' EXIT
cur() { [ -f "$conf" ] && sed -n "s/^$1=//p" "$conf" | head -1 || true; }
# ask <prompt> <default> [regex] [hint]: asks again until the answer matches, so a typo loses nothing.
ask() {
  local v
  while :; do
    read -rp "$1 [$2]: " v || exit 1; v=${v:-$2}
    [[ -z "${3:-}" || "$v" =~ $3 ]] && break
    echo "  $4, try again" >&2
  done
  printf '%s' "$v"
}
# secret_twice <prompt> [min length]: asks again until it gets two matching entries, so a typo loses nothing.
secret_twice() {
  local a b
  while :; do
    read -rsp "$1: " a || exit 1; echo >&2
    [ ${#a} -ge "${2:-1}" ] || { echo "  too short (${2:-1}+ characters), try again" >&2; continue; }
    read -rsp "$1 again: " b || exit 1; echo >&2
    [ "$a" = "$b" ] && break
    echo "  didn't match, try again" >&2
  done
  printf '%s' "$a"
}

id=$(cur ID_SERVER); relay=$(cur RELAY_SERVER); key=$(cur KEY)
echo "Server: in RustDesk, Settings > Network > ID/Relay server > Export server config, then paste here."
while :; do
  read -rp "Paste config (Enter = keep current${id:+: $id}${id:-: public servers}; '-' = public servers): " cfg || exit 1
  [ -z "$cfg" ] && break
  [ "$cfg" != - ] || { id= relay= key=; break; }
  # RustDesk export = base64(JSON {host, relay, api, key}) written backwards.
  if out=$(python3 -c '
import sys, json, base64, re
s = sys.argv[1].strip()[::-1]; s += "=" * (-len(s) % 4)
d = json.loads(base64.b64decode(s))
host, relay, key = (str(d.get(k, "")) for k in ("host", "relay", "key"))
# These land in the installers, so only plain host names / base64 are accepted.
assert all(re.fullmatch(r"[A-Za-z0-9.:\[\]-]*", v) for v in (host, relay)) and re.fullmatch(r"[A-Za-z0-9+/=]*", key)
print(host); print(relay); print(key)' "$cfg" 2>/dev/null); then
    mapfile -t f <<<"$out"
    id=${f[0]:-}; relay=${f[1]:-}; key=${f[2]:-}   # $(...) drops trailing empty lines
    break
  fi
  echo "  that doesn't look like a RustDesk exported server config, try again" >&2
done
echo "  ID server: ${id:-public}  relay: ${relay:-auto}  key: ${key:-none}"

# Suggest the newest stable RustDesk release (Enter takes it); fall back to the profile's version offline.
latest=$(curl -fsSL --max-time 10 https://api.github.com/repos/rustdesk/rustdesk/releases/latest 2>/dev/null |
  python3 -c 'import sys, json; t = json.load(sys.stdin)["tag_name"]; print(t if all(p.isdigit() for p in t.split(".")) else "")' 2>/dev/null || true)
now=$(cur VERSION)
if [ -n "$latest" ] && [ -n "$now" ] && [ "$latest" != "$now" ]; then
  echo "  This profile uses RustDesk $now; the newest is $latest."
fi
ver=$(ask "RustDesk version${latest:+ (Enter = newest)}" "${latest:-${now:-1.5.0}}" '^[0-9.]+$' 'digits and dots only, e.g. 1.5.0')
ts=$(ask "Tailscale (login/key/none)" "$(cur TAILSCALE | grep . || echo none)" '^(login|key|none)$' 'type login, key or none')
brands=$(cd brand-src 2>/dev/null && ls -d */ 2>/dev/null | tr -d / | grep -E '^[a-z0-9-]+$' | tr '\n' / || true)
while :; do
  brand=$(ask "Brand (${brands}none)" "$(cur BRAND | grep . || echo none)")
  [ "$brand" = none ] && { brand=; break; }
  # build.sh's own brand checks, so a brand it would refuse is caught here, before anything is saved.
  "$tool/build.sh" --check-brand "$brand" && break
  echo "  type one of: ${brands}none, or fix that brand first; try again" >&2
done
# Same rule as build.sh: it lands inside quoted strings in the installers.
helper=$(LC_ALL=C ask "Who people should contact (shown in the installer)" "$(cur HELPER | grep . || echo your support person)" '^[A-Za-z0-9 ._,-]+$' 'letters, digits, space . _ , - only')

while :; do
  pw=$(secret_twice "RustDesk password")
  # Windows PowerShell mangles these in the argument it hands RustDesk, silently setting a different password.
  [[ "$pw" != *[\"\\]* ]] && break
  echo '  no " or \ please (Windows cannot pass them to RustDesk), try again' >&2
done
tskey=
[ "$ts" != key ] || tskey=$(secret_twice "Tailscale auth key")
RD_UNLOCK=$(secret_twice "Unlock passphrase (typed at each install; 16+ characters, e.g. 4 random words)" 16)
# The file may float around for years and can be attacked offline, so no short passphrases.
export RD_UNLOCK
# "ok:" prefix lets the installer tell a wrong passphrase from a lucky-padding garbage decrypt.
seal() { [ -z "$1" ] || printf 'ok:%s' "$1" | openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -md sha256 -salt -a -A -pass env:RD_UNLOCK; }

# Encrypt first: a failure inside the heredoc below would not stop the script and would save empty secrets.
pwenc=$(seal "$pw"); tsenc=$(seal "$tskey")
[ -n "$pwenc" ] && { [ -z "$tskey" ] || [ -n "$tsenc" ]; } || { echo "encryption failed (is openssl installed?)" >&2; exit 1; }
cat > "$conf.new" <<EOF
# Made by make.sh $(date +%F). Rerun ./make.sh $name to change.
# Blank ID_SERVER = RustDesk public servers. TAILSCALE: login | key | none
ID_SERVER=$id
RELAY_SERVER=$relay
KEY=$key
VERSION=$ver
TAILSCALE=$ts
HELPER=$helper
BRAND=$brand
PASSWORD_ENC=$pwenc
TS_AUTHKEY_ENC=$tsenc
EOF
mv "$conf.new" "$conf"; saved=1
unset RD_UNLOCK
echo "wrote $conf"
"$tool/build.sh" "$name"
