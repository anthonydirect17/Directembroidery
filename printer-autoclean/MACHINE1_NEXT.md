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

## Next steps (in order)

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

- Machine 2: send the 5 PM 10/7 status line. Expected `Machine - 2  Clean  PASS clean ran (Menu), cap 10 down / 10 up, ended capped, Device Ready`. This is the first live run of the cap check.
- Machine 2 before leaving: switch ON, PrintExp open on Device Ready, PC signed in and unlocked, waste bottle emptied.
- Watchdog routine `trig_01GdobDWLv1cQTg5btVzTvtu` runs in the original cloud session, checking at 9:30 AM and 5:30 PM, active 10/11 5:30 PM to 10/18 9:30 AM. Don't archive that session. It deletes itself after the last check.
- Sticker: waiting on the customer's pick from the blue test sheets (sheet name plus option number).
- Mailbox: next cleanup run around 10/16 to 10/17 (about 10.8 GB) once Recoverable Items purges.
