# Repo Radar

[简体中文说明](./README.zh-CN.md)

Repo Radar turns a local codebase into a compact, interactive project dashboard. It scans on your machine, generates one standalone HTML file, and sends nothing anywhere.

Use it when you have just opened an unfamiliar repository and want a fast answer to four questions: what is here, how is it run, what changed, and what deserves attention first?

## Highlights

- File, directory, size, technology, and language summaries
- Detected start, test, build, lint, and type-check commands
- README, tests, license, CI, and Git worktree signals
- Recent commits, current changes, large files, and TODO-style markers
- Ranked next actions instead of a decorative and scientifically dubious score
- Standalone offline report with light/dark themes and English/Chinese switching
- No installation, package manager, account, server, or network request

## Requirements

- Windows
- Windows PowerShell 5.1 or PowerShell 7
- A modern browser for viewing the generated report
- Git is optional. Without it, branch, commit, and worktree information is unavailable.

## Quick start

Clone the repository and enter its directory:

```powershell
git clone https://github.com/HuangWeiTao-beep/repo-radar.git
cd repo-radar
```

Scan a project and open the report:

```powershell
.\repo-radar.ps1 C:\path\to\your\project -Open
```

The default report is `repo-radar-report.html` in the directory where you ran the command.

### Command Prompt and drag-and-drop

You can also use `repo-radar.cmd`:

```bat
repo-radar.cmd C:\path\to\your\project
```

With no argument, the `.cmd` file scans the current working directory. You can also drag a project folder onto it. The report opens automatically.

## Options

| Option | Purpose | Default |
| --- | --- | --- |
| `-Path` | Project directory to scan; it can also be passed as the first positional argument | Current directory |
| `-Output` | Destination of the generated HTML report | `repo-radar-report.html` in the command's working directory |
| `-MaxFiles` | Maximum number of files to scan; accepted range is 100–100,000 | `20000` |
| `-Open` | Open the report after a successful scan | Off |

Examples:

```powershell
# Scan the current directory
.\repo-radar.ps1 .

# Choose an output location
.\repo-radar.ps1 C:\work\my-app -Output C:\reports\my-app.html

# Scan a large repository and open the result
.\repo-radar.ps1 C:\work\large-repo -MaxFiles 50000 -Open
```

Relative `-Output` paths are resolved from the directory where the command is run, not from the scanned project directory. Missing output directories are created automatically.

## What the numbers mean

Repo Radar combines filesystem data and Git data. They deliberately measure different things.

| Metric | Meaning |
| --- | --- |
| Files | Files found on disk inside the scan scope, including hidden files such as `.gitignore` |
| Directories | Directories actually entered during the scan; the project root counts as one |
| Source size | Combined size of the scanned files |
| Changed | Current entries returned by `git status --short`, not the lifetime number of edits or commits |
| Markers | Matching TODO, FIXME, HACK, and XXX comment lines |
| Recent activity | Up to five latest Git commits |

The output report itself is excluded when it sits inside the project being scanned. Otherwise the scanner would inspect its own previous output and produce increasingly silly numbers.

Git history does not affect the file or directory count. A repository can have hundreds of commits and still contain only nine current files. Likewise, three changed items means three current worktree entries are waiting to be committed; it does not mean three commits exist.

## Scan scope and exclusions

Repo Radar scans the filesystem rather than asking Git for tracked files. A file ignored by `.gitignore` can therefore still be scanned unless it is inside an excluded directory or is the report currently being generated.

The following 18 directory names are skipped by default:

```text
.git          node_modules   dist          build
.next         .nuxt          out           vendor
coverage      .venv          venv          target
bin           obj            __pycache__   .idea
.gradle       .cache
```

Directory links and reparse points are skipped to avoid scan loops. The report footer shows the directories actually skipped during that scan, separately from the full default rule list.

If a directory cannot be read, the report marks the scan as incomplete and lists up to the first 20 affected paths. A partial scan should never dress itself up as a complete one.

When `-MaxFiles` is reached, the scan stops and the report displays a coverage warning. Counts and recommendations then describe only the scanned portion of the repository.

TODO-style content scanning is limited to recognized text files no larger than 1 MB. The report records at most the first 40 matching lines, although the marker total can be higher.

## What the report detects

- Common project manifests and technology markers
- Trustworthy commands declared by the repository, such as `package.json` scripts
- README, test, license, and common CI workflow files
- Git branch, current status, and recent commit subjects
- Files larger than 5 MB
- Sensitive-looking filenames such as `.env`, `.env.*`, private keys, and certificates; environment templates ending in `.example`, `.sample`, or `.template` are ignored
- TODO, FIXME, HACK, and XXX comments

Detection is heuristic. Repo Radar does not execute project commands, install dependencies, or infer commands that are not supported by repository evidence.

## Privacy and security

The scan stays on your machine and the generated report works offline. No source code is uploaded.

The HTML report can contain:

- Project and file paths
- Git commit subjects and worktree filenames
- TODO-style source lines
- Names of sensitive-looking files

Treat the report with the same care as the repository before sharing it. Sensitive-looking files are reported by filename; their secret contents are not embedded. Repo Radar is not a secret scanner, vulnerability scanner, or security audit.

## Troubleshooting

### PowerShell blocks script execution

Run the scanner with a process-scoped bypass:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\repo-radar.ps1 -Path C:\path\to\your\project -Open
```

This does not permanently change the machine's execution policy. Using `repo-radar.cmd` applies the same process-scoped option.

### The report appears outdated

Run the scan again, then refresh the HTML page with `Ctrl+R`. The report is a generated snapshot; it does not watch the repository continuously.

### Git information is missing

Confirm that Git is installed and that the scanned directory is inside a Git worktree:

```powershell
git --version
git -C C:\path\to\your\project status
```

### No project commands were detected

This is expected when the repository has no supported manifest or declared scripts. Repo Radar prefers an empty result to inventing a command that may break the project.

## Development

Run the smoke test from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\smoke.ps1
```

The test verifies report generation, Unicode Git output, Git failure handling, UTC offset formatting, TODO detection, sensitive filename classification, exclusion rules, output exclusion at the scan limit, and the self-scan false-positive regression.

## License

[MIT](./LICENSE)
