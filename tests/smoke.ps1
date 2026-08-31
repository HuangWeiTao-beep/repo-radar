$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$scanner = Join-Path $projectRoot "repo-radar.ps1"
$temporaryBase = [System.IO.Path]::GetTempPath().TrimEnd('\', '/')
$temporaryRoot = Join-Path $temporaryBase ("repo-radar-smoke-" + [Guid]::NewGuid().ToString("N"))
$report = Join-Path $temporaryRoot "report.html"

function Read-ReportData {
    param([string]$ReportPath)

    $reportHtml = [System.IO.File]::ReadAllText($ReportPath, [System.Text.Encoding]::UTF8)
    $dataMatch = [regex]::Match($reportHtml, '(?s)<script id="radar-data" type="application/json">(.*?)</script>')
    if (-not $dataMatch.Success) { throw "Could not find report data in $ReportPath" }

    return [pscustomobject]@{
        Html = $reportHtml
        Data = ($dataMatch.Groups[1].Value | ConvertFrom-Json)
    }
}

try {
    New-Item -ItemType Directory -Path (Join-Path $temporaryRoot "src") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $temporaryRoot "node_modules\fixture-package") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $temporaryRoot "dist") -Force | Out-Null
    $todoKeyword = @('TO', 'DO') -join ''
    [System.IO.File]::WriteAllText((Join-Path $temporaryRoot "README.md"), "# Fixture Project`n")
    [System.IO.File]::WriteAllText((Join-Path $temporaryRoot "package.json"), '{"scripts":{"dev":"vite","test":"vitest","build":"vite build"}}')
    [System.IO.File]::WriteAllText((Join-Path $temporaryRoot "src\main.ts"), "export const answer = 42; // ${todoKeyword}: explain the universe`n")
    [System.IO.File]::WriteAllText((Join-Path $temporaryRoot "src\main.test.ts"), "// smoke test`n")
    [System.IO.File]::WriteAllText((Join-Path $temporaryRoot "node_modules\fixture-package\index.js"), "// ${todoKeyword}: excluded dependency marker`n")
    [System.IO.File]::WriteAllText((Join-Path $temporaryRoot "dist\bundle.js"), "// ${todoKeyword}: excluded build marker`n")

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

    $parsedReport = Read-ReportData -ReportPath $report
    $html = $parsedReport.Html
    $reportData = $parsedReport.Data
    foreach ($expected in @('Fixture Project', 'npm run dev', 'TypeScript', 'TODO: explain the universe', 'Test files detected')) {
        if (-not $html.Contains($expected)) { throw "Report is missing expected content: $expected" }
    }
    if ($html.Contains('__REPO_RADAR_DATA__')) { throw "Template placeholder was not replaced" }

    if (-not $html.Contains('"branch":"main"')) { throw "Git branch was not preserved as main" }
    if (-not $html.Contains($unicodeCommit)) { throw "Unicode Git commit message was corrupted" }
    if ($reportData.generatedAt -notmatch '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC[+-]\d{2}:\d{2}$') { throw "Generated time does not include an explicit UTC offset" }

    $reportedTodos = @($reportData.todos)
    if ($reportedTodos.Count -ne 1 -or $reportedTodos[0].file -ne 'src\main.ts') { throw "Excluded fixture markers leaked into the report" }
    if ($reportData.metrics.files -ne 4) { throw "Excluded directory files were included in the file count" }
    if ($reportData.scan.skippedDirectoryCount -ne 3) { throw "Actual skipped directory count was not reported" }
    if (@($reportData.scan.excludedRules).Count -ne 18) { throw "The report does not use the complete exclusion rule list" }
    $skippedNames = @($reportData.scan.skippedDirectories | ForEach-Object { $_.name })
    foreach ($expectedName in @('.git', 'dist', 'node_modules')) {
        if ($skippedNames -notcontains $expectedName) { throw "Skipped directory type was not reported: $expectedName" }
    }

    $selfScanRoot = Join-Path $temporaryRoot "self-scan"
    $selfScanReport = Join-Path $temporaryRoot "self-scan-report.html"
    New-Item -ItemType Directory -Path $selfScanRoot -Force | Out-Null
    Copy-Item -LiteralPath $MyInvocation.MyCommand.Path -Destination (Join-Path $selfScanRoot "smoke.ps1")
    & powershell -NoProfile -ExecutionPolicy Bypass -File $scanner -Path $selfScanRoot -Output $selfScanReport | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Scanner could not perform the self-marker regression check" }
    $selfScanData = (Read-ReportData -ReportPath $selfScanReport).Data
    if (@($selfScanData.todos).Count -ne 0) { throw "The smoke test source was mistaken for a real TODO marker" }

    Write-Host "Repo Radar smoke test passed." -ForegroundColor Green
} finally {
    $resolvedTemporaryBase = [System.IO.Path]::GetFullPath($temporaryBase).TrimEnd('\') + '\'
    $resolvedTemporaryRoot = [System.IO.Path]::GetFullPath($temporaryRoot)
    if ($resolvedTemporaryRoot.StartsWith($resolvedTemporaryBase, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTemporaryRoot).StartsWith('repo-radar-smoke-')) {
        Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
