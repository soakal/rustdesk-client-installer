# RustDesk client installer

Builds double-click installers that set up the [RustDesk](https://github.com/rustdesk/rustdesk) remote-support
client on someone else's computer, already pointed at your server and with your permanent password, plus
plain-language guides with screenshots for the person running them.

- One **profile** per setup (family, a work team, a client). The RustDesk password (and optional Tailscale
  auth key) is encrypted inside the installer and unlocked by a passphrase you tell the person by phone.
- Works with RustDesk's public servers or your own server, with or without [Tailscale](https://tailscale.com).
- Optional **brand**: your name, colours and icon on the installer window and the desktop/app-menu shortcut.
- Windows (single `.cmd`, one UAC click), Linux (deb/rpm), macOS (untested).

## Make a profile

Needs bash, openssl, curl, python3 (+ Pillow for brands). Run in your own terminal, since it asks for secrets:

```bash
./make.sh family
```

It asks for:
1. The server config exported from RustDesk (Settings > Network > ID/Relay server > Export server config).
   Enter keeps the current one, `-` means RustDesk's public servers.
2. RustDesk version (it suggests the newest release; Enter takes it) and Tailscale mode (`login` / `key` / `none`).
3. Brand (a folder in `brand-src/`, or `none`) and who people should contact, e.g. `the IT desk`.
4. The RustDesk password, a Tailscale auth key (key mode only), and the unlock passphrase (16+ characters).

Output in `dist/family/`:

| File | For |
|---|---|
| `Install-RustDesk-Windows.cmd` | Windows: the one to send. Double-click. |
| `install-unix.sh` | Linux and macOS: `bash install-unix.sh` |
| `install-windows.ps1` | Admins/RMM: `powershell -ExecutionPolicy Bypass -File install-windows.ps1` |
| `guide/windows.md`, `guide/linux.md`, `guide/mac.md` | Step-by-step guides to send with it |

Non-secret lines in a profile can be edited by hand, then `./build.sh family`.

## Profile fields (`profiles/<name>.conf`)

| Field | Meaning |
|---|---|
| `ID_SERVER`, `RELAY_SERVER`, `KEY` | Your server. All 3 blank = RustDesk's public servers. |
| `VERSION` | RustDesk release, e.g. `1.5.0` |
| `TAILSCALE` | `key` (joins with the auth key), `login` (whoever opens the printed link approves the machine), `none` |
| `HELPER` | Who the installer and guides say to contact (default `your support person`) |
| `BRAND` | Folder in `brand-src/` (blank = plain) |
| `PASSWORD_ENC`, `TS_AUTHKEY_ENC` | Written by `make.sh`. Never edit by hand. |

Examples: `profiles/*.conf.example`.

## Brands (`brand-src/<name>/`)

`brand.conf` (`BRAND_NAME`, `TAGLINE`, `CONSOLE_COLOR` = a Windows console colour name, `ANSI_COLOR` = a
terminal colour code), `icon.png` (square, 256 px or more) and optionally `img/` with screenshots that
replace the plain ones in the guides. See `brand-src/example/`. The RustDesk app itself keeps its own name
and logo; only the installer window and the shortcut are branded.

## Sending an installer

1. **Tailscale: use `key` mode** for anyone but yourself, with a pre-approved, reusable auth key (rebuild when
   it expires). In `login` mode whoever opens the link enrolls the machine, possibly into their own account.
2. Send **one file** via a Google Drive / Dropbox / OneDrive link (mail services refuse `.cmd` and `.sh`),
   plus the guide for their system.
3. **Tell the passphrase by phone or in person**, never in the same message as the file. The file may float
   around for years and can be attacked offline.
4. They send you the ID; connect with the profile's RustDesk password.
5. One password per profile: everyone set up from a profile shares it, so make separate profiles for
   separate groups.

## Security notes

- Secrets: AES-256-CBC, PBKDF2-SHA256 600k iterations (`openssl enc`), passphrase 16+ characters.
- RustDesk downloads are checked against the SHA-256 GitHub publishes for that release (stamped in at build
  time); the Tailscale MSI must carry a valid Tailscale Inc signature. Linux Tailscale uses the official
  `install.sh` (signed package repositories).
- The Windows launcher runs the installer from memory; nothing is left in temp folders.

## Private overlay (keeping your profiles and brands in another repo)

Set `RD_ROOT` to a folder with your own `profiles/`, `brand-src/` (and `dist/` is written there):
`RD_ROOT=~/my-setup ./build.sh family`. A private repo can carry this tool in `tool/` (git subtree) with
two-line `make.sh`/`build.sh` wrappers that set `RD_ROOT`.

## Known limits

- macOS: untested. Install and open the Tailscale app first (its VPN prompt needs a person); after install
  open RustDesk once, click *Install service*, allow Screen Recording + Accessibility.
- Linux registers with the server once someone is logged in to a desktop.

## License

MIT. Downloads RustDesk (AGPL-3.0) and Tailscale from their official releases at install time; nothing
from either project is redistributed or modified. Not affiliated with RustDesk or Tailscale.
