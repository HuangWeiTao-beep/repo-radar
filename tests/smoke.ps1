$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$scanner = Join-Path $projectRoot "repo-radar.ps1"
$temporaryBase = [System.IO.Path]::GetTempPath().TrimEnd('\', '/')
$temporaryRoot = Join-Path $temporaryBase ("repo-radar-smoke-" + [Guid]::NewGuid().ToString("N"))
$report = Join-Path $temporaryRoot "report.html"

try {
    New-Item -ItemType Directory -Path (Join-Path $temporaryRoot "src") -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $temporaryRoot "README.md"), "# Fixture Project`n")
    [System.IO.File]::WriteAllText((Join-Path $temporaryRoot "package.json"), '{"scripts":{"dev":"vite","test":"vitest","build":"vite build"}}')
    [System.IO.File]::WriteAllText((Join-Path $temporaryRoot "src\main.ts"), "export const answer = 42; // TODO: explain the universe`n")
    [System.IO.File]::WriteAllText((Join-Path $temporaryRoot "src\main.test.ts"), "// smoke test`n")

    & git -C $temporaryRoot init -b main | Out-Null
    & git -C $temporaryRoot config user.name "Repo Radar Test"
    & git -C $temporaryRoot config user.email "repo-radar@example.invalid"
    & git -C $temporaryRoot config core.autocrlf false
    & git -C $temporaryRoot add .
    $unicodeCommit = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5re75Yqg5Li76KaB6YOo5YiG'))
    $commitMessageFile = Join-Path $temporaryRoot "commit-message.txt"
    [System.IO.File]::WriteAllText($commitMessageFile, $unicodeCommit, [System.Text.UTF8Encoding]::new($false))
    & git -C $temporaryRoot -c i18n.commitEncoding=utf-8 commit -F $commitMessageFile | Out-Null
    Remove-Item -LiteralPath $commitMessageFile -Force
    if ($LASTEXITCODE -ne 0) { throw "Could not create the Git fixture" }

    & powershell -NoProfile -ExecutionPolicy Bypass -File $scanner -Path $temporaryRoot -Output $report | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Scanner exited with code $LASTEXITCODE" }
    if (-not (Test-Path -LiteralPath $report)) { throw "Report was not generated" }

    $html = [System.IO.File]::ReadAllText($report, [System.Text.Encoding]::UTF8)
    foreach ($expected in @('Fixture Project', 'npm run dev', 'TypeScript', 'TODO: explain the universe', 'Test files detected')) {
        if (-not $html.Contains($expected)) { throw "Report is missing expected content: $expected" }
    }
    if ($html.Contains('__REPO_RADAR_DATA__')) { throw "Template placeholder was not replaced" }

    if (-not $html.Contains('"branch":"main"')) { throw "Git branch was not preserved as main" }
    if (-not $html.Contains($unicodeCommit)) { throw "Unicode Git commit message was corrupted" }

    Write-Host "Repo Radar smoke test passed." -ForegroundColor Green
} finally {
    $resolvedTemporaryBase = [System.IO.Path]::GetFullPath($temporaryBase).TrimEnd('\') + '\'
    $resolvedTemporaryRoot = [System.IO.Path]::GetFullPath($temporaryRoot)
    if ($resolvedTemporaryRoot.StartsWith($resolvedTemporaryBase, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTemporaryRoot).StartsWith('repo-radar-smoke-')) {
        Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
