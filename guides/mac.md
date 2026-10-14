# Setting up remote help on your Mac

> Not tested on a real Mac yet; screenshots still to come.

You need: the link to the file, the passphrase (told to you by phone or in person; capital letters matter), the password you use to log in to the Mac, and about 10 minutes.

**Step 1. (Only if your support person told you this setup uses "Tailscale".)**
Open the **App Store**. Search for **Tailscale**. Click **Get**, then **Open**.
A box says *"Tailscale" Would Like to Add VPN Configurations* — click **Allow** (it may ask for your
password). **Do not log in** to Tailscale — just close its window. If your support person didn't mention Tailscale, skip this step.

**Step 2. Download the file.**
Click the link you were sent, click **Download**. The file is `install-unix.sh` and lands in your **Downloads** folder.

**Step 3. Open Terminal.**
Click the **magnifying glass** at the top-right of the screen. Type `Terminal` and press **Enter**.
A white or black window with some text opens. That's Terminal.

**Step 4. Paste this line and press Enter.**
Copy this exactly, click inside the Terminal window, paste it (Command+V), press **Enter**:

```
bash ~/Downloads/install-unix.sh
```

(If you saved the file somewhere other than Downloads: type `bash ` — with a space after it — then
**drag the file** from the Finder into the Terminal window, then press Enter.)

**Step 5. Type your computer password.**
It says *Type the password you use to log in to this computer*. Type it. **Nothing will show up as you
type — not even dots. That's normal.** Press **Enter**.
This must be the main account on the Mac (the one that can install things).

**Step 6. Type the passphrase.**
It says *Type the passphrase your support person gave you*. Type it (again nothing shows). Press **Enter**.

**Step 7. Wait.**
Text scrolls for a few minutes. If it says *"A web link will appear below. Send it to your support person"*: take a
photo of the window, send it to your support person, and wait. It carries on after they open the link.

**Step 8. Send your support person the number.**
You'll see:

```
==================================================================
  ALL DONE. Tell your support person this number:  123456789
==================================================================
```

Send your support person that number. You can close Terminal.

**Step 9. Three permission clicks (Mac only).**
Open **Finder** → **Applications** → double-click **RustDesk**.
1. If it shows a yellow bar or button saying **Install service** (or *Start service*), click it and type your password.
2. A box says *"RustDesk" would like to record this computer's screen*. Click **Open System Settings**,
   turn the switch next to **RustDesk** **on**.
3. Another box asks for **Accessibility**. Same thing: **Open System Settings**, turn **RustDesk** **on**.
If RustDesk asks to **Quit & Reopen**, click it. If the number shown under **Your ID** in the RustDesk
window is different from the one in Step 8, send your support person this one.

**Step 10. That's it.** Keep the Mac plugged in and awake when your support person is going to help.
