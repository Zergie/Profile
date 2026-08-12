# Git prompt live-update smoke test

Run this checklist in both Windows Terminal and a VS Code PowerShell terminal:

- Enter a repository and confirm the prompt appears without waiting for Git.
- Modify, stage, and unstage a file; confirm the marked status row refreshes in place.
- Change branches while text is typed on the input row; confirm the text and cursor stay unchanged.
- Change directory to another repository; confirm notifications for the previous repository do not repaint the prompt.
- Open two PowerShell windows in the same repository and confirm both receive updates.
- Restart the watcher and confirm the last cached prompt remains usable, then live updates resume.
- Print a multiline command or other unmarked terminal output immediately above the cursor; confirm no extra repaint or diagnostic appears.
