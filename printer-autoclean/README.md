# DTF printer auto-clean (PrintExp)

Goal: run a head clean on each DTF printer while the shop is closed, so ink keeps moving through the branch lines and dampers between the white ink main line and the heads.

Nothing here installs software, changes PrintExp settings, or needs the internet. Everything uses tools built into Windows.

## Step 1: inspect PrintExp (read-only)

Run this on **each** printer PC. It clicks nothing and changes nothing.

1. Open PrintExp as usual, connected to the printer. Do not minimize it.
2. Copy `Inspect-PrintExp.ps1` to the PC (USB stick for the laptop).
3. Open **Windows PowerShell** and run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Inspect-PrintExp.ps1
   ```

4. When it says **WATCH STEP**, click **Clean** in PrintExp exactly as you normally do. If a window pops up, leave it open about 5 seconds, then finish or cancel the clean as usual.
5. When it finishes, a `.zip` named `PrintExp-Inspect-<PC name>-<date>` is on the Desktop. Send it back.

What it records: PrintExp version and folder contents, every button and control PrintExp exposes to Windows, screenshots of PrintExp and any pop-up, the Windows version, and the current sleep setting.

## Step 2: the auto-clean script

Built from the Step 1 results. It will:

- Run from Windows Task Scheduler at the times you choose.
- Check that PrintExp is open and that no error box is showing before it does anything.
- Press Clean the same way you do, then take a screenshot and write a log line so you can confirm every run when you get back.
