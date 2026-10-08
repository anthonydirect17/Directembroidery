Thanks, the cap-log theory looks right. Anthony watched all three scripted cleans: caps seated every time and everything looked normal. So the gaps are in PrintExp's log only, most likely because AutoClean.ps1 v1.1 opened the log every 1 to 2 s during the clean.

v1.2.0 fixes that: after choosing Normal it does not open PrintExp's log at all while the clean runs. It watches only the log file's size and time stamp, waits until the log has been quiet for 30 s (at least 90 s after Enter), then reads the log once and does the same VID=57 and cap checks. The settle wait after the clean works the same way. Nothing else changed.

Same ground rules. Do these in order and stop on anything unexpected:

1. From the Drive folder "Printer AutoClean (DTF)", download AutoClean_v1.2.ps1 and save it as C:\DirectTools\printer-autoclean\AutoClean.ps1, replacing v1.1. SHA256 must be 501B9FF8290228FB3D0CCBD16093DB17B403DD4EFA87F4C1736481E4C3BE7815. If it differs, stop.
2. Keep machine-settings.json and config.json as they are. No need to rerun Discover.
3. DryRun: request.txt = DryRun, run. Expect "RESULT: OK dry run: all checks passed" and v1.2.0 in the first log line.
4. Tell Anthony a test clean is about to start (he watches). Delete state\last-clean.txt (with his OK, same as before), then request.txt = Clean, run. It now takes about 2 to 4 minutes because it waits for the clean to finish before reading the log. Expect "RESULT: PASS clean ran (Menu), cap 10 down / 10 up, ended capped, Device Ready".
5. Report: the RESULT line, the cap line sequence from PrintExp's log for this clean (D/U with times, like before), when the clean started and ended, and how long the whole run took. If it still shows gaps, say so; do not run more cleans.
6. Confirm the switch is still OFF. Then remind Anthony to turn the Wi-Fi off.
