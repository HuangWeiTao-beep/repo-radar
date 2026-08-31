# Repo Radar

[简体中文说明](./README.zh-CN.md)

Repo Radar turns any local codebase into a compact, interactive project dashboard. It scans locally, generates one standalone HTML file, and sends nothing anywhere.

## Run it

From PowerShell:

```powershell
.\repo-radar.ps1 C:\path\to\your\project -Open
```

Or double-click `repo-radar.cmd` to scan the current folder and open the report. You can also drag a project folder onto the `.cmd` file.

Useful options:

```powershell
# Choose the report location
.\repo-radar.ps1 . -Output .\my-report.html

# Raise the safety limit for a very large repository
.\repo-radar.ps1 . -MaxFiles 50000 -Open
```

## What it reports

- Project type, language mix, file count, size, and Git branch
- Suggested start, test, build, lint, and type-check commands
- README, tests, license, CI, and worktree health
- Sensitive-looking filenames, large files, and scan coverage warnings
- Ranked next actions, recent commits, changed files, and TODO markers
- One-click English / Simplified Chinese interface switching

Generated reports are self-contained and work offline. Build folders, dependency folders, Git internals, virtual environments, and common caches are skipped by default.

## Privacy and limits

The scan stays on your machine. TODO snippets are included in the generated report, so treat the HTML with the same care as the source repository. Secret-like files are identified by filename only; their contents are never read into the report.
