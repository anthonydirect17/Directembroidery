# Final prep before the trip (leave 10/11, back 10/18)

Go through this the day before leaving (10/10).

## Machine 2 (desktop, online): ready

Live auto-clean test passed 10/7 10:49. Cleans run at 9:00 AM and 5:00 PM once switched ON.

On the day you leave:

- [ ] Empty the waste ink bottle
- [ ] PrintExp open and showing **Device Ready**
- [ ] "DTF AutoClean On-Off" shortcut: click **Turn ON**
- [ ] PC left on, signed in and **unlocked** (do not press Win+L)

When you're back: click **Turn OFF**.

## Machine 1 (laptop, offline): ready

Set up 10/8. Test clean ran 10/8 5:16 PM; Anthony watched it: normal clean, heads capped. The script logged ALERT only because PrintExp skipped some cap lines in its log (same 83 second clean as the hand cleans). On this laptop an ALERT changes nothing: it only goes in the log, cleans keep running, and no email is sent (offline).

On the day you leave:

- [ ] Empty the waste ink bottle
- [ ] Restart the laptop, open PrintExp, wait for **Device Ready** (the restart makes sure only one PrintExp is running)
- [ ] Laptop plugged in, Wi-Fi off
- [ ] "DTF AutoClean On-Off" shortcut: click **Turn ON**
- [ ] Left signed in and **unlocked** (do not press Win+L)

When you're back: click **Turn OFF**. Nothing alerts you about Machine 1 while you're away; results are in `C:\DirectTools\printer-autoclean\logs\`.

## Already covered, nothing to do

- Email cleanup runs on its own (next chunk around 10/16 to 10/17).
- Watchdog emails you if a Machine 2 clean leaves no record (10/11 5:30 PM to 10/18 9:30 AM). Keep the original Claude chat; don't archive it before 10/18.

## After the trip (not before)

- **Run both printers from one PC.** Blocker: both printer boards use the same address (192.168.127.10, port 5001).
  - Network adapters: already have them (each printer has its own 1 Gb USB network adapter).
  - New address for one board: Claude researches where PrintExp sets it and walks Anthony through it, tested carefully (no vendor support).
  - Two PrintExp copies in separate folders (versions differ: 2022 and 2024): explore and test.
  - AutoClean for two windows: not needed until after this trip.
- **Email cleanup on Microsoft's side** (option C), so it no longer depends on a PC.
- **Windows 10 end of support:** decide on extended updates or an upgrade for the printer PCs.
