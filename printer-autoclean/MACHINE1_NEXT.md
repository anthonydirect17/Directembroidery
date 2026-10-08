# Machine 1 (laptop, primary printer): where we left off

Saved 2026-10-07. Pick up here when Anthony says "work on Machine 1".

## Known facts

- Laptop is offline. Windows user `direc`. No email alerts and no Drive status file; runs log locally in `C:\DirectTools\printer-autoclean\logs\`.
- PrintExp path: `C:\Users\direc\Desktop\PrintExp_X64_V5.7.6.5.85.BS_20220304\...` (2022 build, older than Machine 2's 2024 build). Process name `PrintExp_X64`, runs as administrator.
- Printer link: network, 192.168.127.10 port 5001, Established. The AutoClean port check works unchanged.
- **Blocker:** 3 `PrintExp_X64` processes were running. AutoClean requires exactly 1, so every clean would SKIP.
  - 6252, started 2026-08-31, no window, no printer link (leftover)
  - 10016, started 2026-09-25, no window, no printer link (leftover)
  - 11788, started 2026-10-07 10:24 AM, window "PrintExp", owns the printer connection (the real one)
  - The laptop has not restarted since at least 2026-08-31.

## Status 2026-10-08 night: READY

- v1.1 installed, machine-settings.json set, Discover OK (4 head-All > Normal = 21025, TopCount 9), Method Menu, DryRun OK.
- Test clean 17:16:38: ran by Menu, confirmed by VID=57, 83 s (same as hand cleans at 12:40 and 14:44). Result ALERT: PrintExp logged 8 cap down / 5 up, last line down. Anthony at the printer: clean looked normal, heads capped. Hand cleans that day logged 10/10, so this printer's cap logging is not always complete.
- Decision: no script change. On Machine 1 an ALERT is only a log label (no email, cleans continue), so the cap check has no effect here. Switch stays OFF until departure; leave-day checklist in FINAL_PREP.md.

## Status 2026-10-08 evening

- Local session (laptop online, Wi-Fi not set metered) did steps 1 to 3, 7 and 8. Task installed (9:00 and 17:00), shortcut made, switch OFF, sleep/hibernate/lid off.
- Discover stopped: this PrintExp's Clean menu has 9 items ("4 head-All", "4 head-H1~H3", ... "4 head-H4"), not 3, and it logs a clean as VID=57 (Machine 2: VID=31). Machine has 3 heads; Anthony uses **4 head-All > Clean normal** by hand (screenshot confirmed).
- Fix: `AutoClean.ps1` v1.1.0 (SHA256 2077F8AD...6AB7C, Drive `AutoClean_v1.1.ps1`) adds an optional `machine-settings.json`. Machine 1 uses `{ "MenuGroup": "4 head-All", "CleanVid": 57 }`. Without the file v1.1 behaves like v1.0, so Machine 2 keeps v1.0 (5999F335...F644) untouched.
- Next: paste `MACHINE1_FOLLOWUP_PROMPT.md` into the laptop session: install v1.1, settings file, Discover, Discover:1, Method Menu, DryRun, supervised test clean.

## Plan (decided 2026-10-08): short internet session

Anthony connects the laptop to the shop Wi-Fi for one session and a local Claude does steps 2 to 8 below. Prompt: `MACHINE1_LOCAL_PROMPT.md` (also in the Drive folder "Printer AutoClean (DTF)").

Anthony's part:

1. End of the work day: close PrintExp normally, restart the laptop.
2. Before going online: Windows Update > Pause updates (skip if the pause limit is reached).
3. Connect to the shop Wi-Fi and set it to **Metered** right away. If Windows asks to restart while online, say no.
4. From Machine 2, copy `AutoClean.ps1` and `DTF-AutoClean-Switch.ps1` (in `C:\DirectTools\printer-autoclean`) to a USB stick and plug it into the laptop.
5. Open PrintExp, wait for Device Ready.
6. Open Claude on the laptop and paste the prompt. Click Yes on the one admin prompt. Watch the printer during the test clean.
7. Turn the Wi-Fi off and paste the session's report into the cloud chat.

## Detailed steps (what the local session does)

1. End of work day, after any print job finishes: close PrintExp normally, then **restart the laptop**. (Alternative: admin PowerShell `Stop-Process -Id 6252, 10016`.)
2. Open PrintExp once, connect, wait for Device Ready. Confirm `(Get-Process PrintExp_X64).Count` returns **1**.
3. Files: copy `C:\DirectTools\printer-autoclean` from Machine 2 by USB, **without** `state\`, `logs\` and `config.json`. Put `Machine - 1` in `machine-name.txt`. Skip MailSetup (offline).
4. Install the task from an admin PowerShell: `powershell -ExecutionPolicy Bypass -File .\AutoClean.ps1 -Mode Install -Times 09:00,17:00`
5. Discover, with PrintExp idle on Device Ready: write `Discover` to `request.txt`, run the task, check `logs\shots\*_discover-submenu.png` for the position of "Clean normal", then write `Discover:<position>` and run again. Check config.json and set `"Method": "Menu"` if Discover did not.
6. One supervised test clean: write `Clean` to `request.txt`, run the task, watch the cap cycle. The log must end `RESULT: PASS ... cap 10 down / 10 up ...` (cycle count may differ on this printer; the check accepts 8 to 12).
7. Desktop shortcut for `DTF-AutoClean-Switch.ps1`. Leave the switch OFF until departure.
8. Laptop power settings (plugged in and on battery): sleep never, hibernate never, lid close does nothing. Note the battery lasts about 3 h in an outage.
9. Right before leaving on 10/11: confirm the PrintExp count is still 1 (stray copies have appeared before), PrintExp shows Device Ready, the PC is signed in and unlocked, then switch ON.

## Other open items (not Machine 1)

- Machine 2: live end-to-end test PASSED 2026-10-07 10:49 (`Clean PASS clean ran (Menu), cap 10 down / 10 up, ended capped, Device Ready`). Ready; switch is OFF until departure.
- Machine 2 before leaving: switch ON, PrintExp open on Device Ready, PC signed in and unlocked, waste bottle emptied.
- Watchdog routine `trig_01GdobDWLv1cQTg5btVzTvtu` runs in the original cloud session, checking at 9:30 AM and 5:30 PM, active 10/11 5:30 PM to 10/18 9:30 AM. Don't archive that session. It deletes itself after the last check.
- Sticker: waiting on the customer's pick from the blue test sheets (sheet name plus option number).
- Mailbox: next cleanup run around 10/16 to 10/17 (about 10.8 GB) once Recoverable Items purges.
