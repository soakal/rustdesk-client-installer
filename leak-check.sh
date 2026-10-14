#!/usr/bin/env bash
# leak-check.sh: refuse to publish real profiles, private brands or private strings.
# The private strings (names, hostnames, IPs, key prefixes) are NOT in this repo, since listing them would
# leak them: one extended regex per line in $LEAK_PATTERNS (default .git/leak-patterns, never committed).
set -euo pipefail
cd "$(dirname "$0")"
bad=0
files=$(git ls-files)
if grep -E '^profiles/.*\.conf$' <<<"$files"; then echo "^ real profile tracked (only *.conf.example belongs here)"; bad=1; fi
if grep -E '^brand-src/' <<<"$files" | grep -v '^brand-src/example/'; then echo "^ private brand tracked"; bad=1; fi
pat=${LEAK_PATTERNS:-.git/leak-patterns}
if [ -s "$pat" ]; then
  if git grep -I -n -i -E -f "$pat" -- . ':!leak-check.sh'; then echo "^ private string found"; bad=1; fi
  if git log --format='%an %ae %cn %ce %s%n%b' | grep -i -E -f "$pat"; then echo "^ private string in commit messages"; bad=1; fi
  if git log -p --all --format= 2>/dev/null | grep -a -v '^Binary files' | grep -i -E -f "$pat"; then echo "^ private string in an older version of a file"; bad=1; fi
else
  echo "warning: no $pat, so only the file checks ran" >&2
fi
[ "$bad" = 0 ] && echo "leak-check: clean"
exit $bad
