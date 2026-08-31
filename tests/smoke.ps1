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

    & powershell -NoProfile -ExecutionPolicy Bypass -File $scanner -Path $temporaryRoot -Output $report | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Scanner exited with code $LASTEXITCODE" }
    if (-not (Test-Path -LiteralPath $report)) { throw "Report was not generated" }

    $html = Get-Content -Raw -LiteralPath $report
    foreach ($expected in @('Fixture Project', 'npm run dev', 'TypeScript', 'TODO: explain the universe', 'Test files detected')) {
        if (-not $html.Contains($expected)) { throw "Report is missing expected content: $expected" }
    }
    if ($html.Contains('__REPO_RADAR_DATA__')) { throw "Template placeholder was not replaced" }

    Write-Host "Repo Radar smoke test passed." -ForegroundColor Green
} finally {
    $resolvedTemporaryBase = [System.IO.Path]::GetFullPath($temporaryBase).TrimEnd('\') + '\'
    $resolvedTemporaryRoot = [System.IO.Path]::GetFullPath($temporaryRoot)
    if ($resolvedTemporaryRoot.StartsWith($resolvedTemporaryBase, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTemporaryRoot).StartsWith('repo-radar-smoke-')) {
        Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
