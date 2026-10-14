#!/usr/bin/env bash
# RustDesk (+ Tailscale) installer for Linux and macOS.   Run:  bash <this file>
# It asks for your computer password itself (sudo), then the unlock passphrase.
# Built by build.sh: the profile below is stamped in, secrets are encrypted.
set -euo pipefail
[ "$(id -u)" = 0 ] || exec sudo -p 'Type the password you use to log in to this computer (nothing shows as you type), then press Enter: ' -- bash "$0" "$@"
umask 022   # menu entry/icon must be readable by the desktop user
tmp=$(mktemp -d)
# exit 3 = something the person can fix themselves (message already printed); anything else gets the banner.
trap 'rc=$?; rm -rf "$tmp"; [ "$rc" = 0 ] || [ "$rc" = 3 ] || { echo; echo "*** SOMETHING WENT WRONG. Take a photo of this window and send it to __HELPER__. ***" >&2; }' EXIT
oops() { echo "$*" >&2; exit 3; }
say() { echo; echo "==> $*"; }
# Run a noisy installer step quietly; show its output only if it fails.
quiet() { "$@" > "$tmp/log" 2>&1 || { cat "$tmp/log" >&2; return 1; }; }

PROFILE=$(cat <<'__END_PROFILE__'
__PROFILE__
__END_PROFILE__
)
get() { printf '%s\n' "$PROFILE" | sed -n "s/^$1=//p" | head -1; }

BRAND=$(get BRAND); BRAND_NAME=$(get BRAND_NAME)
if [ -n "$BRAND_NAME" ]; then
  c=$(get ANSI_COLOR); bar="=================================================================="; tag=$(get TAGLINE)
  printf '\033[%sm%s\033[0m\n  \033[1m%s%s\033[0m\n\033[%sm%s\033[0m\n' "$c" "$bar" "$BRAND_NAME" "${tag:+  -  $tag}" "$c" "$bar"
fi
echo "This sets up RustDesk so __HELPER__ can help you with this computer. It takes a few minutes."
say "First, the unlock passphrase"
# RD_UNLOCK in the environment skips the prompt (unattended/RMM use, run as root: sudo drops it).
[ -n "${RD_UNLOCK:-}" ] || { read -rsp "Type the passphrase __HELPER__ gave you (nothing shows as you type), then press Enter: " RD_UNLOCK </dev/tty; echo; }
export RD_UNLOCK
unlock() {
  local t; t=$(printf '%s' "$1" | openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -md sha256 -a -A -pass env:RD_UNLOCK 2>/dev/null) &&
    [ "${t#ok:}" != "$t" ] && printf '%s' "${t#ok:}"
}
bad_pass="That passphrase didn't work. Run this again and type it carefully - capital letters matter."
PW=$(unlock "$(get PASSWORD_ENC)") || oops "$bad_pass"
TS_MODE=$(get TAILSCALE)
TSKEY=; [ "$TS_MODE" != key ] || TSKEY=$(unlock "$(get TS_AUTHKEY_ENC)") || oops "$bad_pass"
unset RD_UNLOCK   # decrypted everything we need; don't hand the passphrase to apt, curl|sh, etc.
VER=$(get VERSION)
OS=$(uname -s)
# Only x86_64 packages are stamped in; refuse before changing anything.
[ "$OS" = Darwin ] || [ "$(uname -m)" = x86_64 ] || oops "This installer only supports Intel/AMD Linux computers. Tell __HELPER__."

# --- Tailscale ---
if [ "$TS_MODE" != none ]; then
  say "Setting up the secure connection (Tailscale)"
  ts=tailscale
  if [ "$OS" = Darwin ]; then
    ts=/Applications/Tailscale.app/Contents/MacOS/Tailscale
    # The Mac app needs its VPN/system-extension prompts clicked by a person, so no silent install.
    [ -x "$ts" ] || oops "Please install the Tailscale app first: open the App Store, search for Tailscale, click Get, open it once and click Allow. Then run this again."
  elif ! command -v tailscale >/dev/null; then
    quiet sh -c 'curl -fsSL https://tailscale.com/install.sh | sh'
  fi
  if ! "$ts" status >/dev/null 2>&1; then
    if [ "$TS_MODE" = key ]; then
      printf '%s' "$TSKEY" > "$tmp/k"; chmod 600 "$tmp/k"
      quiet "$ts" up --auth-key="file:$tmp/k"; rm -f "$tmp/k"
    else
      echo "A web link will appear below. Send it to __HELPER__ (a photo of this window is fine) and wait here."
      echo "This continues by itself once __HELPER__ opens the link."
      "$ts" up
    fi
  fi
fi

# --- RustDesk ---
say "Downloading and installing RustDesk (about a minute)"
url="https://github.com/rustdesk/rustdesk/releases/download/$VER/rustdesk-$VER"
# Refuse a download whose SHA-256 differs from the one GitHub published for this release (stamped in by build.sh).
verify() {
  local want got; want=$(get "$1")
  got=$( { sha256sum "$2" 2>/dev/null || shasum -a 256 "$2"; } | cut -d' ' -f1)
  [ -n "$want" ] && [ "$got" = "$want" ] || { echo "The RustDesk download did not pass its safety check. Try again later." >&2; exit 1; }
}
if [ "$OS" = Darwin ]; then
  arch=$([ "$(uname -m)" = arm64 ] && echo aarch64 || echo x86_64)
  curl -fsSL -o "$tmp/rd.dmg" "$url-$arch.dmg"
  verify "$([ "$arch" = aarch64 ] && echo SHA_DMG_ARM64 || echo SHA_DMG_X64)" "$tmp/rd.dmg"
  mnt=$(hdiutil attach "$tmp/rd.dmg" -nobrowse | awk -F'\t' '/\/Volumes/{print $NF}')
  rm -rf /Applications/RustDesk.app
  cp -R "$mnt/RustDesk.app" /Applications/
  hdiutil detach "$mnt" -quiet
  rd=/Applications/RustDesk.app/Contents/MacOS/RustDesk
elif command -v apt-get >/dev/null; then
  curl -fsSL -o "$tmp/rd.deb" "$url-x86_64.deb"
  verify SHA_DEB "$tmp/rd.deb"
  chmod 711 "$tmp"   # apt's sandbox user must be able to reach the package
  DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a quiet apt-get install -y "$tmp/rd.deb"
  rd=rustdesk
elif command -v dnf >/dev/null; then
  curl -fsSL -o "$tmp/rd.rpm" "$url-0.x86_64.rpm"
  verify SHA_RPM "$tmp/rd.rpm"
  quiet dnf install -y "$tmp/rd.rpm"
  rd=rustdesk
else
  echo "unsupported OS" >&2; exit 1
fi
[ "$OS" = Darwin ] || quiet systemctl enable --now rustdesk
# Mac: --install-service does nothing there; only the button in the app installs the service settings need.
svc=/Library/LaunchDaemons/com.carriez.RustDesk_service.plist
if [ "$OS" = Darwin ] && [ ! -f "$svc" ]; then
  say "One click needed: RustDesk is opening. Click 'Install service' in its window (type your computer password if asked)."
  sudo -u "${SUDO_USER:-root}" open -a /Applications/RustDesk.app || true
  for _ in $(seq 150); do [ -f "$svc" ] && break; sleep 2; done
  [ -f "$svc" ] || oops "'Install service' wasn't clicked in RustDesk. Run this again."
fi

# Linux keeps RustDesk's settings per logged-in desktop user. With nobody logged in they are accepted
# (Done!) but lost at the next login, so wait for the desktop user's RustDesk to be running.
# A login screen (gdm/sddm/lightdm) can run one too, so it must belong to a real desktop session's user.
desktop_rd() {
  local s
  for s in $(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $1}'); do
    [ "$(loginctl show-session "$s" -p Class --value 2>/dev/null)" = user ] || continue
    case $(loginctl show-session "$s" -p Type --value 2>/dev/null) in x11|wayland) ;; *) continue;; esac
    ps -C rustdesk -o uid=,args= | awk -v u="$(loginctl show-session "$s" -p User --value)" '$1 == u && /--server/' | grep -q . && return 0
  done
  return 1
}
if [ "$OS" = Linux ]; then
  for _ in $(seq 15); do desktop_rd && break; sleep 2; done
  desktop_rd || oops "Log in to this computer's desktop first (someone must be signed in on the screen), then run this again."
fi

say "Applying settings"
# RustDesk exits 0 even when a setting fails. Only "Done!" proves the password reached the running service,
# so retry while it starts, and do it first so the options below also go to the service, not a stray file.
for _ in $(seq 15); do
  out=$("$rd" --password "$PW" 2>&1 || true)
  case $out in *Done!*) break;; esac
  sleep 2
done
case $out in *Done!*) ;; *)
  echo "$out" >&2
  [ "$OS" = Darwin ] || echo "RustDesk didn't take its settings. Run this from the desktop (not over SSH) while logged in." >&2
  exit 1;; esac
# Blank = clear, so switching to a profile with public servers or no key drops the old values. Silent = success.
# Read each one back too: RustDesk can drop a write without saying so.
for opt in custom-rendezvous-server:ID_SERVER relay-server:RELAY_SERVER key:KEY; do
  k=${opt%%:*}; v=$(get "${opt#*:}")
  # stdout only: its messages are println, stderr may carry GTK/loader noise
  out=$("$rd" --option "$k" "$v" 2>/dev/null) && [ -z "$out" ] && got=$("$rd" --option "$k" 2>/dev/null) && [ "$got" = "$v" ] ||
    { echo "${out:-RustDesk did not keep setting $k}" >&2; exit 1; }
done
# Ask the service once more: if it stopped answering mid-way, the options above went to a local file instead.
case $("$rd" --password "$PW" 2>&1 || true) in *Done!*) ;; *) echo "RustDesk stopped answering while taking its settings." >&2; exit 1;; esac
# The server can reject a reused ID (e.g. a reimaged PC) and RustDesk then picks a new one.
# Linux registers once someone is logged in to a desktop, so the ID may still change after that.
sleep 20
ID=$("$rd" --get-id 2>/dev/null || true)
# Linux: an app-menu entry with the brand's name and icon (RustDesk's own entry stays). Never fatal.
if [ "$OS" = Linux ] && [ -n "$BRAND_NAME" ]; then
  { get ICON_PNG_B64 | base64 -d > "/usr/share/icons/hicolor/256x256/apps/$BRAND-support.png" &&
    printf '[Desktop Entry]\nType=Application\nName=%s\nExec=rustdesk\nIcon=%s-support\nCategories=Network;RemoteAccess;\n' \
      "$BRAND_NAME" "$BRAND" > "/usr/share/applications/$BRAND-support.desktop" &&
    { gtk-update-icon-cache -q /usr/share/icons/hicolor 2>/dev/null || true; }
  } || echo "(Could not add the $BRAND_NAME menu entry. RustDesk still works.)"
fi
echo
printf '\033[32m%s\n  ALL DONE. Tell __HELPER__ this number:  %s\n%s\033[0m\n' "==================================================================" \
  "${ID:-(open RustDesk and read the number under 'Your ID')}" "=================================================================="
[ "$OS" != Darwin ] || echo "One more thing on a Mac: in RustDesk, click Allow/Open System Settings on the Screen Recording and Accessibility pop-ups."
echo "You can close this window now."
