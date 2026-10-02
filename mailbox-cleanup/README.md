# Mailbox cleanup (direct@sarasotashirts.com)

Keeps the mailbox to a rolling 2-year window. Mail older than 2 years is deleted oldest first, across all folders. Everything newer is never touched.

## Why it runs in chunks

Deleted mail goes to Microsoft's hidden Recoverable Items folder. That folder does not count against the 99 GB quota, and items stay restorable there for 14 days. But it has its own 30 GB hard limit, and if it fills up nobody can delete anything. So each run deletes at most 15 GB and checks that the folder stays under 15 GB. The backlog clears over a few runs about 2 weeks apart. After that, each daily run only trims the mail that turned 2 years old that day.

## One-time setup (about 10 minutes)

1. Copy the `mailbox-cleanup` folder to the PC, for example `C:\DirectTools\mailbox-cleanup`.
2. Right-click `MailboxCleanup.ps1` > Properties > tick **Unblock** if shown > OK.
3. Open **Windows PowerShell** (normal, not admin) and run:

   ```powershell
   cd C:\DirectTools\mailbox-cleanup
   powershell -ExecutionPolicy Bypass -File .\MailboxCleanup.ps1
   ```

4. A browser opens. Sign in as direct@sarasotashirts.com. Microsoft asks to allow **Microsoft Graph Command Line Tools** to read and write your mail. Accept. If it says admin approval is needed, sign in as the admin and approve for the organization.
5. The script prints a report: how many old messages and GB per folder. **Nothing is changed.** The full list is saved as `logs\Report_<date>.csv`.

## Deleting

| Step | Command | What it does |
|---|---|---|
| Test | `.\MailboxCleanup.ps1 -Mode Delete -TestOne` | Deletes only the single oldest message. Check that it shows in Outlook on the web under Deleted Items > **Recover items deleted from this folder**. |
| First real run | `.\MailboxCleanup.ps1 -Mode Delete` | Deletes up to 15 GB, oldest first. Type `DELETE` to confirm. Takes roughly 20 to 40 minutes. |
| Automate | `.\MailboxCleanup.ps1 -InstallSchedule -ScheduleTime 02:30` | Runs every day at 2:30 AM while you are logged in. Missed runs catch up when the PC wakes. |

(Prefix each with `powershell -ExecutionPolicy Bypass -File` if PowerShell refuses to run scripts.)

The storage page in Outlook on the web can take a few hours to show the new number.

## Optional backup

Add `-BackupPath D:\MailBackup` to save a full copy of every message (attachments included) as an `.eml` file before it is deleted. Files are sorted into `Folder\Year\`. A message is only deleted after its copy is saved.

- Size: about the same as the mail being removed.
- Open a file by double-clicking it (Outlook or Windows Mail).
- Restore by dragging `.eml` files into a folder in classic Outlook.

## Files

- `logs\` run logs, `Report_*.csv` (what would be deleted), `Deleted_*.csv` (what was deleted). Logs older than 120 days are removed automatically.
- `state\refresh-token.dat` the saved sign-in, encrypted so only this Windows user on this PC can use it. Run `-SignOut` or delete it to forget the sign-in. Never share or commit it.

## Other options

| Option | Use |
|---|---|
| `-KeepYears 3` | Keep 3 years instead of 2. |
| `-MaxGBPerRun 10` | Smaller chunks. |
| `-UninstallSchedule` | Remove the daily task. |
| `-SignOut` | Forget the saved sign-in. |

The saved sign-in lasts as long as the script runs at least once every 90 days. If it expires, run the script once by hand to sign in again.
