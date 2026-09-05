[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Path = ".",

    [string]$Output = (Join-Path (Get-Location) "repo-radar-report.html"),

    [ValidateRange(100, 100000)]
    [int]$MaxFiles = 20000,

    [switch]$Open
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$excludedDirectoryNames = @(
    '.git', 'node_modules', 'dist', 'build', '.next', '.nuxt', 'out', 'vendor',
    'coverage', '.venv', 'venv', 'target', 'bin', 'obj', '__pycache__', '.idea',
    '.gradle', '.cache'
)

function Get-RelativePathSafe {
    param([string]$BasePath, [string]$TargetPath)

    $base = [System.IO.Path]::GetFullPath($BasePath).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $target = [System.IO.Path]::GetFullPath($TargetPath)
    $baseUri = [Uri]::new($base)
    $targetUri = [Uri]::new($target)
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString()).Replace('/', '\')
}

function Invoke-Git {
    param([string]$Root, [string[]]$Arguments)

    try {
        # Read Git through a byte-aware process stream. Windows PowerShell 5.1
        # otherwise decodes native output with the active console code page,
        # which corrupts UTF-8 branch names and commit messages.
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = "git"
        $startInfo.WorkingDirectory = $Root
        $startInfo.Arguments = $Arguments -join ' '
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
        $startInfo.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEnd()
        [void]$process.StandardError.ReadToEnd()
        $process.WaitForExit()
        $exitCode = $process.ExitCode
        $process.Dispose()

        if ($exitCode -eq 0 -and $stdout.Length -gt 0) {
            return @($stdout.TrimEnd("`r", "`n") -split "`r?`n")
        }
    } catch { }
    return @()
}

function Get-ScannableFiles {
    param(
        [System.IO.DirectoryInfo]$Root,
        [int]$Limit,
        [string[]]$ExcludedDirectoryNames
    )

    $excluded = @{}
    foreach ($name in $ExcludedDirectoryNames) {
        $excluded[$name] = $true
    }

    $files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    $stack = [System.Collections.Generic.Stack[System.IO.DirectoryInfo]]::new()
    $skippedDirectoryCounts = @{}
    $stack.Push($Root)
    $directoryCount = 0
    $limited = $false
    $reparsePointCount = 0

    while ($stack.Count -gt 0) {
        $directory = $stack.Pop()
        $directoryCount++

        try {
            foreach ($file in $directory.GetFiles()) {
                if ($files.Count -ge $Limit) { $limited = $true; break }
                $files.Add($file)
            }
        } catch { }

        if ($limited) { break }

        try {
            foreach ($child in $directory.GetDirectories()) {
                if ($excluded.ContainsKey($child.Name)) {
                    if ($skippedDirectoryCounts.ContainsKey($child.Name)) {
                        $skippedDirectoryCounts[$child.Name]++
                    } else {
                        $skippedDirectoryCounts[$child.Name] = 1
                    }
                    continue
                }

                if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                    $reparsePointCount++
                    continue
                }

                $stack.Push($child)
            }
        } catch { }
    }

    $skippedDirectories = @(
        $skippedDirectoryCounts.GetEnumerator() |
            Sort-Object Name |
            ForEach-Object { [pscustomobject]@{ name = $_.Name; count = $_.Value } }
    )
    $skippedDirectoryCount = [int](($skippedDirectories | Measure-Object count -Sum).Sum)

    return [pscustomobject]@{
        Files = $files
        DirectoryCount = $directoryCount
        Limited = $limited
        SkippedDirectories = $skippedDirectories
        SkippedDirectoryCount = $skippedDirectoryCount
        ReparsePointCount = $reparsePointCount
    }
}

function Add-Command {
    param(
        [System.Collections.Generic.List[object]]$List,
        [string]$Label,
        [string]$Command,
        [string]$Reason,
        [string]$ReasonKey
    )

    if (-not ($List | Where-Object { $_.command -eq $Command })) {
        $List.Add([pscustomobject]@{ label = $Label; command = $Command; reason = $Reason; reasonKey = $ReasonKey })
    }
}

$resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
$rootItem = Get-Item -LiteralPath $resolved.Path
if (-not $rootItem.PSIsContainer) { throw "Path must be a directory: $Path" }

$root = $rootItem.FullName
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$templatePath = Join-Path $scriptRoot "src\report-template.html"
$outputFullPath = [System.IO.Path]::GetFullPath($Output)
if (-not (Test-Path -LiteralPath $templatePath)) {
    throw "Report template is missing: $templatePath"
}

$scan = Get-ScannableFiles -Root $rootItem -Limit $MaxFiles -ExcludedDirectoryNames $excludedDirectoryNames
$files = @($scan.Files | Where-Object { $_.FullName -ne $outputFullPath })
$relativeFiles = @{}
foreach ($file in $files) {
    $relativeFiles[$file.FullName] = Get-RelativePathSafe -BasePath $root -TargetPath $file.FullName
}

$markerMap = [ordered]@{
    "package.json" = "Node.js"; "tsconfig.json" = "TypeScript"; "pyproject.toml" = "Python";
    "requirements.txt" = "Python"; "Cargo.toml" = "Rust"; "go.mod" = "Go";
    "composer.json" = "PHP"; "pom.xml" = "Java / Maven"; "build.gradle" = "Java / Gradle";
    "Gemfile" = "Ruby"; "pubspec.yaml" = "Flutter / Dart"; "Package.swift" = "Swift"
}

$fileNameSet = @{}
foreach ($file in $files) { $fileNameSet[$file.Name.ToLowerInvariant()] = $true }

$rootFileNameSet = @{}
foreach ($file in $files | Where-Object { $_.DirectoryName -eq $root }) {
    $rootFileNameSet[$file.Name.ToLowerInvariant()] = $true
}

$technologies = [System.Collections.Generic.List[string]]::new()
foreach ($marker in $markerMap.Keys) {
    if ($fileNameSet.ContainsKey($marker.ToLowerInvariant()) -and -not $technologies.Contains($markerMap[$marker])) {
        $technologies.Add($markerMap[$marker])
    }
}

$languageMap = @{
    ".ts" = "TypeScript"; ".tsx" = "TypeScript"; ".js" = "JavaScript"; ".jsx" = "JavaScript";
    ".mjs" = "JavaScript"; ".cjs" = "JavaScript"; ".py" = "Python"; ".rs" = "Rust";
    ".go" = "Go"; ".java" = "Java"; ".kt" = "Kotlin"; ".kts" = "Kotlin";
    ".cs" = "C#"; ".cpp" = "C++"; ".cc" = "C++"; ".c" = "C"; ".h" = "C / C++";
    ".php" = "PHP"; ".rb" = "Ruby"; ".swift" = "Swift"; ".dart" = "Dart";
    ".vue" = "Vue"; ".svelte" = "Svelte"; ".html" = "HTML"; ".css" = "CSS";
    ".scss" = "SCSS"; ".sql" = "SQL"; ".sh" = "Shell"; ".ps1" = "PowerShell"
}

$languageBytes = @{}
foreach ($file in $files) {
    $extension = $file.Extension.ToLowerInvariant()
    if ($languageMap.ContainsKey($extension)) {
        $language = $languageMap[$extension]
        if (-not $languageBytes.ContainsKey($language)) { $languageBytes[$language] = 0L }
        $languageBytes[$language] += $file.Length
    }
}
$totalCodeBytes = [double](($languageBytes.Values | Measure-Object -Sum).Sum)
$languages = @($languageBytes.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 8 | ForEach-Object {
    [pscustomobject]@{
        name = $_.Key
        bytes = $_.Value
        percent = if ($totalCodeBytes -gt 0) { [math]::Round(($_.Value / $totalCodeBytes) * 100, 1) } else { 0 }
    }
})

$extensionStats = @($files | Group-Object { if ($_.Extension) { $_.Extension.ToLowerInvariant() } else { "[none]" } } |
    Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object {
        [pscustomobject]@{ extension = $_.Name; count = $_.Count }
    })

$textExtensions = @(
    ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".py", ".rs", ".go", ".java", ".kt",
    ".cs", ".cpp", ".cc", ".c", ".h", ".php", ".rb", ".swift", ".dart", ".vue", ".svelte",
    ".html", ".css", ".scss", ".sql", ".sh", ".ps1", ".md", ".yaml", ".yml", ".json", ".toml"
)
$todos = [System.Collections.Generic.List[object]]::new()
$todoTotal = 0
$markerPattern = '(?:#|//|/\*|<!--|--)\s*(?:TODO|FIXME|HACK|XXX)\b'
foreach ($file in $files) {
    if ($file.Length -gt 1MB -or -not ($textExtensions -contains $file.Extension.ToLowerInvariant())) { continue }
    try {
        $matches = @(Select-String -LiteralPath $file.FullName -Pattern $markerPattern -AllMatches -ErrorAction SilentlyContinue)
        $todoTotal += $matches.Count
        foreach ($match in $matches) {
            if ($todos.Count -ge 40) { break }
            $line = ($match.Line.Trim() -replace '\s+', ' ')
            if ($line.Length -gt 180) { $line = $line.Substring(0, 177) + "..." }
            $kindMatch = [regex]::Match($match.Line, '(?i)\b(TODO|FIXME|HACK|XXX)\b')
            $kind = $kindMatch.Groups[1].Value.ToUpperInvariant()
            $todos.Add([pscustomobject]@{
                kind = $kind
                file = $relativeFiles[$file.FullName]
                line = $match.LineNumber
                text = $line
            })
        }
    } catch { }
}

$readme = $files | Where-Object { $_.Name -match '^README(\..+)?$' } | Select-Object -First 1
$license = $files | Where-Object { $_.Name -match '^(LICENSE|LICENCE)(\..+)?$' } | Select-Object -First 1
$hasTests = [bool]($files | Where-Object {
    $_.DirectoryName -match '[\\/](tests?|spec|__tests__)([\\/]|$)' -or $_.BaseName -match '(\.test|\.spec|_test)$'
} | Select-Object -First 1)
$hasCi = [bool]($files | Where-Object {
    $relativeFiles[$_.FullName] -match '^\.github\\workflows\\|^\.gitlab-ci\.yml$|^azure-pipelines\.yml$'
} | Select-Object -First 1)

$sensitiveNames = @('.env', '.env.local', '.env.production', 'id_rsa', 'id_dsa')
$sensitiveFiles = @($files | Where-Object {
    $sensitiveNames -contains $_.Name.ToLowerInvariant() -or $_.Extension.ToLowerInvariant() -in @('.pem', '.p12', '.pfx', '.key')
} | ForEach-Object { $relativeFiles[$_.FullName] })
$largeFiles = @($files | Where-Object { $_.Length -gt 5MB } | Sort-Object Length -Descending | Select-Object -First 8 | ForEach-Object {
    [pscustomobject]@{ file = $relativeFiles[$_.FullName]; megabytes = [math]::Round($_.Length / 1MB, 1) }
})

$gitAvailable = [bool](Get-Command git -ErrorAction SilentlyContinue)
$gitRoot = ""
$branch = "Not under Git"
$statusLines = @()
$commits = @()
if ($gitAvailable) {
    $gitRootResult = @(Invoke-Git -Root $root -Arguments @('rev-parse', '--show-toplevel'))
    if ($gitRootResult.Count -gt 0) {
        $gitRoot = [string]$gitRootResult[0]
        $branchResult = @(Invoke-Git -Root $root -Arguments @('branch', '--show-current'))
        $branch = if ($branchResult.Count -gt 0 -and $branchResult[0]) { [string]$branchResult[0] } else { "Detached HEAD" }
        $statusLines = @(Invoke-Git -Root $root -Arguments @('status', '--short'))
        $logLines = @(Invoke-Git -Root $root -Arguments @('log', '-5', '--pretty=format:%h|%ad|%s', '--date=short'))
        $commits = @($logLines | ForEach-Object {
            $parts = $_ -split '\|', 3
            if ($parts.Count -eq 3) { [pscustomobject]@{ hash = $parts[0]; date = $parts[1]; subject = $parts[2] } }
        })
    }
}

$commands = [System.Collections.Generic.List[object]]::new()
$packageFile = $files | Where-Object { $_.Name -eq 'package.json' -and $_.DirectoryName -eq $root } | Select-Object -First 1
if ($packageFile) {
    $manager = if ($rootFileNameSet.ContainsKey('pnpm-lock.yaml')) { 'pnpm' } elseif ($rootFileNameSet.ContainsKey('yarn.lock')) { 'yarn' } elseif ($rootFileNameSet.ContainsKey('bun.lockb') -or $rootFileNameSet.ContainsKey('bun.lock')) { 'bun' } else { 'npm' }
    try {
        $package = Get-Content -Raw -LiteralPath $packageFile.FullName | ConvertFrom-Json
        $scriptNames = @($package.scripts.PSObject.Properties.Name)
        foreach ($scriptName in @('dev', 'start', 'test', 'build', 'lint', 'typecheck', 'check')) {
            if ($scriptNames -contains $scriptName) {
                $run = if ($manager -eq 'npm') { "npm run $scriptName" } else { "$manager $scriptName" }
                Add-Command -List $commands -Label $scriptName -Command $run -Reason "package.json script" -ReasonKey "reasonPackageScript"
            }
        }
    } catch { }
}
if ($fileNameSet.ContainsKey('pyproject.toml') -or $fileNameSet.ContainsKey('requirements.txt')) {
    Add-Command -List $commands -Label "test" -Command "python -m pytest" -Reason "Python project" -ReasonKey "reasonPython"
}
if ($fileNameSet.ContainsKey('cargo.toml')) { Add-Command -List $commands -Label "test" -Command "cargo test" -Reason "Rust project" -ReasonKey "reasonRust" }
if ($fileNameSet.ContainsKey('go.mod')) { Add-Command -List $commands -Label "test" -Command "go test ./..." -Reason "Go project" -ReasonKey "reasonGo" }
if ($files | Where-Object { $_.Extension -eq '.sln' } | Select-Object -First 1) { Add-Command -List $commands -Label "test" -Command "dotnet test" -Reason ".NET solution" -ReasonKey "reasonDotNet" }
if ($fileNameSet.ContainsKey('pom.xml')) { Add-Command -List $commands -Label "test" -Command "mvn test" -Reason "Maven project" -ReasonKey "reasonMaven" }
if ($fileNameSet.ContainsKey('gradlew') -or $fileNameSet.ContainsKey('gradlew.bat')) { Add-Command -List $commands -Label "test" -Command ".\gradlew test" -Reason "Gradle wrapper" -ReasonKey "reasonGradle" }

$health = [System.Collections.Generic.List[object]]::new()
$health.Add([pscustomobject]@{ label = "README"; labelKey = "healthReadme"; state = if ($readme) { "good" } else { "warn" }; detail = if ($readme) { $relativeFiles[$readme.FullName] } else { "No README found" }; detailKey = if ($readme) { $null } else { "noReadme" }; count = 0 })
$health.Add([pscustomobject]@{ label = "Tests"; labelKey = "healthTests"; state = if ($hasTests) { "good" } else { "warn" }; detail = if ($hasTests) { "Test files detected" } else { "No test files detected" }; detailKey = if ($hasTests) { "testsDetected" } else { "noTests" }; count = 0 })
$health.Add([pscustomobject]@{ label = "License"; labelKey = "healthLicense"; state = if ($license) { "good" } else { "info" }; detail = if ($license) { $relativeFiles[$license.FullName] } else { "No license detected" }; detailKey = if ($license) { $null } else { "noLicense" }; count = 0 })
$health.Add([pscustomobject]@{ label = "Automation"; labelKey = "healthAutomation"; state = if ($hasCi) { "good" } else { "info" }; detail = if ($hasCi) { "CI workflow detected" } else { "No CI workflow detected" }; detailKey = if ($hasCi) { "ciDetected" } else { "noCi" }; count = 0 })
$health.Add([pscustomobject]@{ label = "Git worktree"; labelKey = "healthGit"; state = if (-not $gitRoot) { "warn" } elseif ($statusLines.Count -eq 0) { "good" } else { "warn" }; detail = if (-not $gitRoot) { "Not under Git" } elseif ($statusLines.Count -eq 0) { "Clean" } else { "$($statusLines.Count) changed item(s)" }; detailKey = if (-not $gitRoot) { "notUnderGit" } elseif ($statusLines.Count -eq 0) { "clean" } else { "changedItems" }; count = $statusLines.Count })

$risks = [System.Collections.Generic.List[object]]::new()
if ($sensitiveFiles.Count -gt 0) {
    $risks.Add([pscustomobject]@{ level = "high"; title = "Sensitive-looking files"; titleKey = "riskSensitive"; detail = "$($sensitiveFiles.Count) credential or environment file(s) found. Confirm they are ignored and contain no committed secrets."; detailKey = "riskSensitiveDetail"; count = $sensitiveFiles.Count; items = $sensitiveFiles })
}
if ($largeFiles.Count -gt 0) {
    $risks.Add([pscustomobject]@{ level = "medium"; title = "Large files"; titleKey = "riskLarge"; detail = "$($largeFiles.Count) file(s) exceed 5 MB and may slow clones or reviews."; detailKey = "riskLargeDetail"; count = $largeFiles.Count; items = @($largeFiles | ForEach-Object { "$($_.file) ($($_.megabytes) MB)" }) })
}
if ($scan.Limited) {
    $risks.Add([pscustomobject]@{ level = "medium"; title = "Scan limit reached"; titleKey = "riskLimit"; detail = "Stopped after $MaxFiles files. Increase -MaxFiles for a complete report."; detailKey = "riskLimitDetail"; count = $MaxFiles; items = @() })
}
if (-not $hasTests -and $files.Count -gt 5) {
    $risks.Add([pscustomobject]@{ level = "medium"; title = "No tests detected"; titleKey = "riskNoTests"; detail = "Changes have no obvious automated safety net."; detailKey = "riskNoTestsDetail"; count = 0; items = @() })
}
if ($todoTotal -gt 20) {
    $risks.Add([pscustomobject]@{ level = "low"; title = "TODO backlog"; titleKey = "riskTodos"; detail = "$todoTotal TODO-style markers detected. Some may be harmless, but the pile deserves a look."; detailKey = "riskTodosDetail"; count = $todoTotal; items = @() })
}

$actions = [System.Collections.Generic.List[object]]::new()
if (-not $gitRoot) { $actions.Add([pscustomobject]@{ priority = "P1"; title = "Put the project under version control"; titleKey = "actionGit"; detail = "Initialize Git before making meaningful changes."; detailKey = "actionGitDetail"; count = 0 }) }
elseif ($statusLines.Count -gt 0) { $actions.Add([pscustomobject]@{ priority = "P1"; title = "Review the current worktree"; titleKey = "actionReview"; detail = "$($statusLines.Count) changed item(s) are waiting. Understand these before stacking on more work."; detailKey = "actionReviewDetail"; count = $statusLines.Count }) }
if ($sensitiveFiles.Count -gt 0) { $actions.Add([pscustomobject]@{ priority = "P1"; title = "Verify sensitive files are ignored"; titleKey = "actionSensitive"; detail = "Check environment and key files without exposing their contents."; detailKey = "actionSensitiveDetail"; count = 0 }) }
if (-not $readme) { $actions.Add([pscustomobject]@{ priority = "P2"; title = "Write the shortest useful README"; titleKey = "actionReadme"; detail = "Explain what this is, how to run it, and how to verify a change."; detailKey = "actionReadmeDetail"; count = 0 }) }
if (-not $hasTests -and $files.Count -gt 5) { $actions.Add([pscustomobject]@{ priority = "P2"; title = "Add one high-value smoke test"; titleKey = "actionTest"; detail = "Cover the main path first; a giant test framework can wait."; detailKey = "actionTestDetail"; count = 0 }) }
if ($todoTotal -gt 0) { $actions.Add([pscustomobject]@{ priority = "P3"; title = "Triage TODO markers"; titleKey = "actionTodos"; detail = "$todoTotal marker(s) found. Delete stale notes and promote real work into tracked tasks."; detailKey = "actionTodosDetail"; count = $todoTotal }) }
if ($actions.Count -eq 0) { $actions.Add([pscustomobject]@{ priority = "P3"; title = "Run the existing checks"; titleKey = "actionChecks"; detail = "The repository looks orderly. Verify it before choosing the next change."; detailKey = "actionChecksDetail"; count = 0 }) }
$actions = @($actions | Select-Object -First 3)

$projectTitle = Split-Path -Leaf $root
if (-not $projectTitle) { $projectTitle = $root }
if ($readme) {
    try {
        $firstHeading = Get-Content -LiteralPath $readme.FullName -TotalCount 30 | Where-Object { $_ -match '^#\s+(.+)$' } | Select-Object -First 1
        if ($firstHeading) { $projectTitle = ($firstHeading -replace '^#\s+', '').Trim() }
    } catch { }
}

$totalBytes = [long](($files | Measure-Object Length -Sum).Sum)
$data = [ordered]@{
    generatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss 'UTC'zzz")
    project = [ordered]@{
        name = $projectTitle
        path = $root
        branch = $branch
        branchKey = if ($branch -eq "Not under Git") { "notUnderGit" } elseif ($branch -eq "Detached HEAD") { "detachedHead" } else { $null }
        git = [bool]$gitRoot
    }
    metrics = [ordered]@{
        files = $files.Count
        directories = $scan.DirectoryCount
        sizeBytes = $totalBytes
        changed = $statusLines.Count
        todos = $todoTotal
    }
    technologies = @($technologies)
    languages = $languages
    extensions = $extensionStats
    commands = @($commands)
    health = @($health)
    risks = @($risks)
    actions = $actions
    todos = @($todos)
    todoTruncated = ($todoTotal -gt $todos.Count)
    commits = $commits
    changes = @($statusLines | Select-Object -First 30)
    changesTruncated = ($statusLines.Count -gt 30)
    scan = [ordered]@{
        limited = $scan.Limited
        maxFiles = $MaxFiles
        excludedRules = @($excludedDirectoryNames)
        skippedDirectories = @($scan.SkippedDirectories)
        skippedDirectoryCount = $scan.SkippedDirectoryCount
        reparsePointCount = $scan.ReparsePointCount
    }
}

$json = $data | ConvertTo-Json -Depth 8 -Compress
$json = $json.Replace('</', '<\/')
$template = [System.IO.File]::ReadAllText($templatePath, [System.Text.Encoding]::UTF8)
if (-not $template.Contains('__REPO_RADAR_DATA__')) { throw "Template data placeholder not found." }
$html = $template.Replace('__REPO_RADAR_DATA__', $json)

$outputDirectory = Split-Path -Parent $outputFullPath
if (-not (Test-Path -LiteralPath $outputDirectory)) { New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null }
[System.IO.File]::WriteAllText($outputFullPath, $html, [System.Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "Repo Radar report ready" -ForegroundColor Green
Write-Host "Project : $root"
Write-Host "Scanned : $($files.Count) files in $($scan.DirectoryCount) directories"
Write-Host "Report  : $outputFullPath"
if ($scan.Limited) { Write-Warning "The scan stopped at the $MaxFiles file limit." }

if ($Open) { Start-Process $outputFullPath }
