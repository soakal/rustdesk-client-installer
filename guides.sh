#!/usr/bin/env bash
# guides.sh <profile> [out-dir]: render the Windows, Linux and Mac guides for a profile, with its support
# contact (HELPER) and brand name filled in and the brand's screenshots (brand-src/<brand>/img/) laid over
# the plain ones (guides/img/). Needs no passwords. Default output: dist/<profile>/guide/ (build.sh runs this).
set -euo pipefail
tool=$(cd "$(dirname "$0")" && pwd)
export RD_ROOT=${RD_ROOT:-$tool}
cd "$RD_ROOT"
[[ "${1:-}" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "usage: guides.sh <profile> [out-dir]" >&2; exit 1; }
conf="profiles/$1.conf"
[ -f "$conf" ] || { echo "no $conf" >&2; exit 1; }
val() { sed -n "s/^$1=//p" "$2" | head -1; }
helper=$(val HELPER "$conf"); helper=${helper:-your support person}
brand=$(val BRAND "$conf"); title=RustDesk
[ -z "$brand" ] || title=$(val BRAND_NAME "brand-src/$brand/brand.conf")
g=${2:-dist/$1/guide}; mkdir -p "$g/img"
for os in windows linux mac; do
  python3 - "$tool/guides/$os.md" "$helper" "$title" > "$g/$os.md" <<'PY'
import re, sys
text, helper, title = open(sys.argv[1]).read(), sys.argv[2], sys.argv[3]
if helper != "your support person":
    text = re.sub(r"[Yy]our(\s+)support(\s+)person", lambda m: helper if m.group(0)[0] == "y" else helper[0].upper() + helper[1:], text)
if title != "RustDesk":
    text = text.replace("remote help", title, 1)
sys.stdout.write(text)
PY
done
cp "$tool"/guides/img/*.png "$g/img/"
[ -z "$brand" ] || [ ! -d "brand-src/$brand/img" ] || cp "brand-src/$brand"/img/*.png "$g/img/"
echo "guides: $g/"
