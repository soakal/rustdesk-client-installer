#!/usr/bin/env bash
# build.sh <profile>: stamps profiles/<profile>.conf into dist/<profile>/
#   install-unix.sh            Linux + macOS:  bash install-unix.sh
#   install-windows.ps1        admins/RMM:     powershell -ExecutionPolicy Bypass -File install-windows.ps1
#   Install-RustDesk-Windows.cmd  the one to hand to people: double-click (= launcher.cmd + the .ps1)
set -euo pipefail
# The tool (templates, guides) lives next to this script; profiles/, brand-src/ and dist/ live in RD_ROOT
# (a private repo that keeps the tool in tool/), or next to the script when RD_ROOT is unset.
tool=$(cd "$(dirname "$0")" && pwd)
export RD_ROOT=${RD_ROOT:-$tool}
cd "$RD_ROOT"
[[ "${1:-}" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "usage: build.sh <profile>  (letters, digits, - and _)" >&2; exit 1; }
conf="profiles/$1.conf"
[ -f "$conf" ] || { echo "no $conf" >&2; exit 1; }
grep -q '^PASSWORD_ENC=.' "$conf" || { echo "PASSWORD_ENC empty: run ./make.sh $1 first" >&2; exit 1; }
mkdir -p "dist/$1"
val() { sed -n "s/^$1=//p" "$2" | head -1; }
# Text that lands inside bash "...", PowerShell '...', sed and the cmd title: plain characters only.
plain() { LC_ALL=C; [[ -z "$2" || "$2" =~ ^[A-Za-z0-9\ ._,-]+$ ]] || { echo "$1: letters, digits, space . _ , - only" >&2; exit 1; }; }
# HELPER= in the profile is who the installer tells people to contact (no names by default).
helper=$(val HELPER "$conf"); helper=${helper:-your support person}; plain HELPER "$helper"
ver=$(val VERSION "$conf"); [[ "$ver" =~ ^[0-9.]+$ ]] || { echo "VERSION: digits and dots only" >&2; exit 1; }
title=RustDesk
win=$(mktemp) unix=$(mktemp); trap 'rm -f "$win" "$unix" "$win.sha"' EXIT
# SHA-256 of each RustDesk download for this VERSION, as published by GitHub; the installers refuse
# anything that doesn't match (a tampered download, a bad mirror, TLS interception).
curl -fsSL "https://api.github.com/repos/rustdesk/rustdesk/releases/tags/$ver" | python3 -c '
import sys, json
names = {"SHA_EXE_X64": "x86_64.exe", "SHA_EXE_ARM64": "aarch64.exe", "SHA_DEB": "x86_64.deb",
         "SHA_RPM": "0.x86_64.rpm", "SHA_DMG_X64": "x86_64.dmg", "SHA_DMG_ARM64": "aarch64.dmg"}
ver = sys.argv[1]
d = {a["name"]: (a.get("digest") or "") for a in json.load(sys.stdin)["assets"]}
for key, suffix in names.items():
    dg = d.get(f"rustdesk-{ver}-{suffix}", "")
    if dg.startswith("sha256:"): print(f"{key}={dg[7:]}")
' "$ver" > "$win.sha" || { echo "could not fetch RustDesk $ver checksums from GitHub" >&2; exit 1; }
grep -q '^SHA_EXE_X64=' "$win.sha" || { echo "no published checksums for RustDesk $ver" >&2; exit 1; }
{ cat "$conf"; cat "$win.sha"; } | tee "$unix" > "$win"; rm -f "$win.sha"
brand=$(val BRAND "$conf")
if [ -n "$brand" ]; then
  # BRAND=<name> pulls in brand-src/<name>/brand.conf and its icon.png (shortcut/app-menu icon).
  [[ "$brand" =~ ^[a-z0-9-]+$ ]] || { echo "BRAND: a-z 0-9 - only" >&2; exit 1; }
  bdir="brand-src/$brand"
  [ -f "$bdir/brand.conf" ] && [ -f "$bdir/icon.png" ] || { echo "no $bdir/brand.conf + icon.png" >&2; exit 1; }
  for k in BRAND_NAME TAGLINE; do plain "$k" "$(val $k "$bdir/brand.conf")"; done
  [[ "$(val CONSOLE_COLOR "$bdir/brand.conf")" =~ ^[A-Za-z]*$ && "$(val ANSI_COLOR "$bdir/brand.conf")" =~ ^[0-9\;]*$ ]] ||
    { echo "$bdir/brand.conf: CONSOLE_COLOR letters only, ANSI_COLOR digits and ; only" >&2; exit 1; }
  title=$(val BRAND_NAME "$bdir/brand.conf")
  grep -v '^#' "$bdir/brand.conf" | tee -a "$unix" >> "$win"
  python3 - "$bdir/icon.png" >> "$win" 2>/dev/null <<'PY' || { echo "icon: python3 + Pillow needed" >&2; exit 1; }
import sys, io, base64; from PIL import Image
b = io.BytesIO(); Image.open(sys.argv[1]).save(b, 'ICO', sizes=[(16, 16), (32, 32), (48, 48), (256, 256)])
print('ICON_B64=' + base64.b64encode(b.getvalue()).decode())
PY
  python3 - "$bdir/icon.png" >> "$unix" <<'PY'
import sys, io, base64; from PIL import Image
b = io.BytesIO(); Image.open(sys.argv[1]).convert('RGBA').resize((256, 256), Image.LANCZOS).save(b, 'PNG', optimize=True)
print('ICON_PNG_B64=' + base64.b64encode(b.getvalue()).decode())
PY
fi
stamp() { sed -e "/^__PROFILE__\$/{r $1" -e 'd}' -e "s|__HELPER__|$helper|g" "$tool/templates/$2" > "dist/$3/$2"; }
stamp "$unix" install-unix.sh "$1"
stamp "$win" install-windows.ps1 "$1"
chmod +x "dist/$1/install-unix.sh"
# cmd.exe wants CRLF; the launcher's last line is the #__PS__ marker the PowerShell part is cut at.
sed "s|__TITLE__|$title|" "$tool/templates/launcher.cmd" | cat - "dist/$1/install-windows.ps1" | sed 's/$/\r/' > "dist/$1/Install-RustDesk-Windows.cmd"
"$tool/guides.sh" "$1"
echo "built dist/$1/ (installers + guide/)"
