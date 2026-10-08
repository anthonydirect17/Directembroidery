You are helping set up an automatic printhead clean on this laptop ("Machine 1"), a DTF printer PC at Direct Embroidery. I (Anthony) leave on a trip 10/11 and come back 10/18. The same setup already runs on our other printer PC ("Machine 2") and passed a live test there. This laptop normally has NO internet. I connected it to the shop Wi-Fi only for this session.

GROUND RULES
- I am very busy. Do the work yourself. Ask me only when you need a click from me (a Yes on an admin prompt) or a decision.
- Do not install, update or uninstall anything. Do not change Windows Update settings. Do not restart the PC.
- Do not edit AutoClean.ps1 or DTF-AutoClean-Switch.ps1. If something seems to need a change, stop and explain what and why in your report. Changes get reviewed first.
- Never click or type in PrintExp yourself. Only AutoClean.ps1 talks to PrintExp.
- No em dashes or en dashes in anything you write for me.

STEP 0. INTERNET SAFETY (do this first)
- Confirm the Wi-Fi connection is set to Metered. If it is not, tell me and wait until I set it.
- Tell me if Windows Update shows anything waiting for a restart.

STEP 1. PRINTEXP
- (Get-Process PrintExp_X64).Count must be 1. If it is more than 1, stop and tell me. Leftover copies make every clean skip, and a restart fixes it.
- PrintExp must show Device Ready and must not be printing. If it is printing, wait.
- Report only, change nothing: check whether anything starts PrintExp automatically (Startup folders, HKCU and HKLM Run keys, scheduled tasks). Last week 3 copies were running at once.

STEP 2. FILES
- I copied AutoClean.ps1 and DTF-AutoClean-Switch.ps1 from Machine 2 onto a USB stick. Copy only those 2 files to C:\DirectTools\printer-autoclean (create the folder).
- Report the SHA256 of AutoClean.ps1. The reviewed copy starts 5999F335 and ends F644. If it differs, just tell me; do not stop.
- Create machine-name.txt in that folder containing: Machine - 1
- No alert-email.txt and no MailSetup. This PC is offline, so the script skips email and the Drive status file on its own.
- Read DTF-AutoClean-Switch.ps1 and tell me if anything in it is specific to Machine 2 (paths, user names) and would not work here. Do not change it.

STEP 3. INSTALL THE SCHEDULE (needs admin; I will click Yes on the prompt)
  powershell -ExecutionPolicy Bypass -File C:\DirectTools\printer-autoclean\AutoClean.ps1 -Mode Install -Times 09:00,17:00
Confirm the task "Direct Embroidery DTF AutoClean" exists with daily triggers at 9:00 AM and 5:00 PM, runs as this user, highest privileges.

HOW TO RUN A TEST (steps 4 to 6)
Write one word into C:\DirectTools\printer-autoclean\request.txt, then run:
  schtasks /run /tn "Direct Embroidery DTF AutoClean"
Wait for it to finish, then read the newest logs\AutoClean_<date>.log. A request older than 15 minutes is ignored, so write it right before running.

STEP 4. DISCOVER (no clean: it opens the Clean menu, reads it, and closes it without choosing anything)
- request.txt = Discover, run the task.
- Open logs\shots\*_discover-submenu.png yourself and find the position of "Clean normal" under "2 head-All" (0 = top). On Machine 2 the order was weak, normal, strong, so normal was 1. Only use a position you can actually see in the screenshot.
- request.txt = Discover:<position>, run again. Expect "RESULT: OK discover".
- Edit config.json and set "Method": "Menu" (the method tested on Machine 2). This is the only file edit allowed.
- This laptop has the 2022 PrintExp; Machine 2 has the 2024 one. If Discover says the Clean button was not found, or the menu looks different from 3 choices (2 head-All, H1, H2), stop and report with the log lines and the screenshots.

STEP 5. DRY RUN
request.txt = DryRun, run. Expect "RESULT: OK dry run: all checks passed".

STEP 6. ONE TEST CLEAN (I watch the printer; tell me right before you start)
- request.txt = Clean, run. Expect "RESULT: PASS clean ran (Menu), cap N down / N up, ended capped, Device Ready".
- If the result is ALERT or FAIL, stop and report everything. Do not retry.

STEP 7. ON-OFF SHORTCUT
Desktop shortcut named "DTF AutoClean On-Off" that runs:
  powershell -ExecutionPolicy Bypass -File C:\DirectTools\printer-autoclean\DTF-AutoClean-Switch.ps1
Leave the switch OFF (state\autoclean-on.txt must not exist).

STEP 8. POWER AND LOCK
- Plugged in and on battery: sleep never, hibernate never, closing the lid does nothing. The display turning off is fine.
- The scheduled task only works while I am signed in and the PC is unlocked. Check for anything that would lock it while I am away (screen saver with "show logon screen", Dynamic Lock, sign-in required after the display turns off) and tell me what you find. Ask before changing those.

STEP 9. REPORT
A short list: each step OK or the problem, plus the SHA256, the PrintExp path and version, the Discover result, the test clean RESULT line, anything that auto-starts PrintExp, and the power and lock changes made. I will paste it into my other Claude chat. Then remind me to turn the Wi-Fi off.
