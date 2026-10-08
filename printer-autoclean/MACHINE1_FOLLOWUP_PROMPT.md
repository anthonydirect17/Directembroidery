The reviewed change is ready. Anthony confirmed that by hand he uses Clean > 4 head-All > Clean normal on this printer (3 heads, but this is the option he uses).

What changed (AutoClean.ps1 v1.1.0): an optional machine-settings.json now sets the head group ("MenuGroup") and the clean log code ("CleanVid"). Discover saves the group and the number of top-level menu items in config.json, and the menu path checks both. Without machine-settings.json it behaves exactly like v1.0 (2 head-All, 3 items, VID=31), so Machine 2 is unaffected.

Same ground rules as before. Do these in order and stop on anything unexpected:

1. From the Drive folder "Printer AutoClean (DTF)", download AutoClean_v1.1.ps1 and save it as C:\DirectTools\printer-autoclean\AutoClean.ps1, replacing v1.0. Its SHA256 must be 2077F8ADAD1761282B2500F95341C9E6E5BF29359AB005C8C5BEC0DE1E26AB7C. If it differs, stop.
2. Create C:\DirectTools\printer-autoclean\machine-settings.json containing exactly:
   { "MenuGroup": "4 head-All", "CleanVid": 57 }
3. If config.json exists, delete it.
4. Discover: request.txt = Discover, run the task. The log's first line should show group='4 head-All' cleanVid=57. Check the new discover-submenu screenshot: the order should be Clean weak, Clean normal, Clean strong (normal = position 1). Then request.txt = Discover:1, run again. Expect "RESULT: OK discover: 4 head-All > Normal = command <id>, keyboard path ok". Report the command ID (probably 21025). config.json should show AllPos 0, NormalPos 1, MenuGroup "4 head-All", TopCount 9.
5. Edit config.json: set "Method": "Menu". No other edits.
6. DryRun: request.txt = DryRun, run. Expect "RESULT: OK dry run: all checks passed".
7. Test clean with Anthony watching (tell him right before): request.txt = Clean, run. Expect "RESULT: PASS clean ran (Menu), cap N down / N up, ended capped, Device Ready". If ALERT or FAIL, stop and report the full log of that run. Do not retry.
8. Confirm the switch is still OFF (state\autoclean-on.txt does not exist). The scheduled task does not need reinstalling.
9. Short report: SHA256, Discover result and command ID, DryRun result, the test clean RESULT line with the cap counts, and the PrintExp log lines from the clean (the VID=57 line and the first few cap lines). Then remind Anthony to turn the Wi-Fi off.
