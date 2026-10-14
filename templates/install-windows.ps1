# RustDesk (+ Tailscale) installer for Windows. People double-click Install-RustDesk-Windows.cmd,
# which wraps this. Admins/RMM:  powershell -ExecutionPolicy Bypass -File install-windows.ps1
# Built by build.sh: the profile below is stamped in, secrets are encrypted. Keep this file ASCII.
#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$P = @'
__PROFILE__
'@ | ConvertFrom-StringData

# Decrypts `openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -md sha256 -a` output (see make.sh).
function Unlock([string]$b64, [string]$pass) {
  $raw = [Convert]::FromBase64String($b64)
  $kdf = [Security.Cryptography.Rfc2898DeriveBytes]::new($pass, [byte[]]$raw[8..15], 600000, [Security.Cryptography.HashAlgorithmName]::SHA256)
  $kb = $kdf.GetBytes(48)
  $aes = [Security.Cryptography.Aes]::Create()
  $aes.Key = [byte[]]$kb[0..31]; $aes.IV = [byte[]]$kb[32..47]
  $ct = [byte[]]$raw[16..($raw.Length - 1)]
  $bad = 'That passphrase did not work. Run this again and type it carefully - capital letters matter.'
  try { $txt = [Text.Encoding]::UTF8.GetString($aes.CreateDecryptor().TransformFinalBlock($ct, 0, $ct.Length)) }
  catch { throw $bad }
  if (-not $txt.StartsWith('ok:', [StringComparison]::Ordinal)) { throw $bad }
  $txt.Substring(3)
}
function Say($msg) { Write-Host ''; Write-Host "==> $msg" -ForegroundColor Cyan }

$tmp = New-Item -ItemType Directory (Join-Path $env:TEMP ([guid]::NewGuid()))
try {
  if ($P.BRAND_NAME) {
    $bar = '=================================================================='
    Write-Host $bar -ForegroundColor $P.CONSOLE_COLOR
    Write-Host ('  ' + $P.BRAND_NAME + $(if ($P.TAGLINE) { '  -  ' + $P.TAGLINE })) -ForegroundColor White
    Write-Host $bar -ForegroundColor $P.CONSOLE_COLOR
  }
  Write-Host 'This sets up RustDesk so __HELPER__ can help you with this computer. It takes a few minutes.'
  Say 'First, the unlock passphrase'
  # $env:RD_UNLOCK skips the prompt (unattended/RMM use).
  $pass = if ($env:RD_UNLOCK) { $env:RD_UNLOCK } else { [Net.NetworkCredential]::new('', (Read-Host 'Type the passphrase __HELPER__ gave you (you will see * as you type), then press Enter' -AsSecureString)).Password }
  $pw = Unlock $P.PASSWORD_ENC $pass
  $ver = $P.VERSION

  # --- Tailscale ---
  if ($P.TAILSCALE -ne 'none') {
    Say 'Setting up the secure connection (Tailscale)'
    $ts = "$env:ProgramFiles\Tailscale\tailscale.exe"
    if (-not (Test-Path $ts)) {
      $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
      Invoke-WebRequest "https://pkgs.tailscale.com/stable/tailscale-setup-latest-$arch.msi" -OutFile "$tmp\ts.msi"
      # "latest" has no fixed hash, so check it is really signed by Tailscale before running it as admin.
      $sig = Get-AuthenticodeSignature "$tmp\ts.msi"
      if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch '(^|, )O="?Tailscale Inc\.?"?(,|$)') { throw 'The Tailscale download did not pass its safety check. Try again later.' }
      $m = Start-Process msiexec -ArgumentList "/i `"$tmp\ts.msi`" /qn TS_NOLAUNCH=true" -Wait -PassThru
      if ($m.ExitCode -notin 0, 3010) { throw "Tailscale did not install (error $($m.ExitCode))." }
    }
    & $ts status *> $null
    if ($LASTEXITCODE -ne 0) {
      if ($P.TAILSCALE -eq 'key') {
        [IO.File]::WriteAllText("$tmp\k", (Unlock $P.TS_AUTHKEY_ENC $pass))  # not Set-Content: module logging would record the key
        & $ts up --unattended "--auth-key=file:$tmp\k"
      } else {
        Write-Host 'A web link will appear below. Send it to __HELPER__ (a photo of this window is fine) and wait here.'
        Write-Host 'This continues by itself once __HELPER__ opens the link.'
        & $ts up --unattended
      }
      if ($LASTEXITCODE -ne 0) { throw 'Tailscale could not connect (the error is just above).' }
    }
  }

  # --- RustDesk ---
  Say 'Downloading and installing RustDesk (about a minute). A RustDesk window may pop up - leave it alone.'
  $rdarch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'aarch64' } else { 'x86_64' }
  Invoke-WebRequest "https://github.com/rustdesk/rustdesk/releases/download/$ver/rustdesk-$ver-$rdarch.exe" -OutFile "$tmp\rd.exe"
  $want = if ($rdarch -eq 'aarch64') { $P.SHA_EXE_ARM64 } else { $P.SHA_EXE_X64 }
  if (-not $want -or (Get-FileHash "$tmp\rd.exe" -Algorithm SHA256).Hash -ne $want) { throw 'The RustDesk download did not pass its safety check. Try again later.' }
  # No -Wait: the installer leaves RustDesk running, so -Wait would never return.
  Start-Process "$tmp\rd.exe" -ArgumentList '--silent-install'
  $rd = "$env:ProgramFiles\RustDesk\rustdesk.exe"
  # Wait for this version, not just any rustdesk.exe: an upgrade starts with the old one already there.
  $ok = { (Test-Path $rd) -and (Get-Item $rd).VersionInfo.ProductVersion -like "$ver*" }
  for ($i = 0; $i -lt 60 -and -not (& $ok); $i++) { Start-Sleep 2 }
  if (-not (& $ok)) { throw "RustDesk $ver install did not finish in 2 minutes" }
  if (-not (Get-Service RustDesk -ErrorAction SilentlyContinue)) { & $rd --install-service | Out-Null; Start-Sleep 5 }
  Say 'Applying settings'
  # RustDesk exits 0 even when a setting fails. Only "Done!" proves the password reached the running service,
  # so retry while it starts, and do it first so the options below also go to the service, not a stray file.
  for ($i = 0; $i -lt 15; $i++) {
    try { Start-Service RustDesk } catch {}   # the installer may still be registering it; retried here
    $out = & $rd --password $pw | Out-String
    if ($out -match 'Done!') { break }
    Start-Sleep 2
  }
  if ($out -notmatch 'Done!') { throw "RustDesk did not take its settings: $out" }
  # Blank = clear, so switching to a profile with public servers or no key drops the old values. Silent = success.
  # '""' because Windows PowerShell drops a plain '' argument.
  foreach ($o in @{ 'custom-rendezvous-server' = $P.ID_SERVER; 'relay-server' = $P.RELAY_SERVER; 'key' = $P.KEY }.GetEnumerator()) {
    $out = & $rd --option $o.Key $(if ($o.Value) { $o.Value } else { '""' }) | Out-String
    if ($out.Trim()) { throw "RustDesk did not take setting $($o.Key): $out" }
  }
  # The server can reject a reused ID (e.g. a reimaged PC) and RustDesk then picks a new one,
  # so give it time to register before reporting.
  Start-Sleep 20
  $id = (& $rd --get-id | Out-String).Trim()
  if (-not $id) { $id = '(open RustDesk and read the number under "Your ID")' }
  # Branded shortcut last (RustDesk's own installer writes its shortcuts asynchronously) and never fatal.
  if ($P.ICON_B64) {
    try {
      $ico = "$env:ProgramFiles\RustDesk\$($P.BRAND)-support.ico"   # one file per brand: Windows caches icons by path
      [IO.File]::WriteAllBytes($ico, [Convert]::FromBase64String($P.ICON_B64))
      $shell = New-Object -ComObject WScript.Shell
      foreach ($dir in "$env:PUBLIC\Desktop", "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\RustDesk") {
        if (-not (Test-Path $dir)) { continue }
        $lnk = $shell.CreateShortcut("$dir\$($P.BRAND_NAME).lnk")
        $lnk.TargetPath = $rd; $lnk.IconLocation = "$ico,0"; $lnk.Save()
      }
      Remove-Item "$env:PUBLIC\Desktop\RustDesk.lnk" -ErrorAction SilentlyContinue
    } catch { Write-Host "(Could not add the $($P.BRAND_NAME) shortcut. RustDesk still works.)" -ForegroundColor Yellow }
  }
  Write-Host ''
  Write-Host '==================================================================' -ForegroundColor Green
  Write-Host "  ALL DONE. Tell __HELPER__ this number:  $id" -ForegroundColor Green
  Write-Host '==================================================================' -ForegroundColor Green
  Write-Host 'You can close this window now.'
} catch {
  Write-Host ''
  Write-Host '*** SOMETHING WENT WRONG. Take a photo of this window and send it to __HELPER__. ***' -ForegroundColor Red
  Write-Host "*** $($_.Exception.Message)" -ForegroundColor Red
  exit 1
} finally {
  Remove-Item $tmp -Recurse -Force
}
