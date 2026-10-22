# ==============================================================================
# Framework Compliance Checker (Slacker Survivors) - PowerShell Edition
# ==============================================================================
# Automated quality gate for architectural boundaries, naming conventions,
# dependency injection rules, and full GDScript syntax compilation.
#
# Usage:
#   pwsh .agents/skills/framework-aware/scripts/check_compliance.ps1
# ==============================================================================

[CmdletBinding()]
param()

$root = (Get-Item $PSScriptRoot).Parent.Parent.Parent.Parent.FullName
Write-Host "[Framework-Aware] Scanning architecture compliance: $root" -ForegroundColor Cyan
Write-Host "--------------------------------------------------------" -ForegroundColor Cyan

$errorCount = 0
$warnCount = 0

function Sync-GodotGlobalClassCache {
    param([string]$ProjectRoot)
    $cachePath = Join-Path $ProjectRoot ".godot\global_script_class_cache.cfg"
    if (-not (Test-Path (Split-Path $cachePath -Parent))) {
        return
    }
    $scanDirs = @("src", "addons") | ForEach-Object { Join-Path $ProjectRoot $_ } | Where-Object { Test-Path $_ }
    $entries = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($file in (Get-ChildItem -Path $scanDirs -Recurse -Filter *.gd -File -ErrorAction SilentlyContinue)) {
        $lines = [System.IO.File]::ReadAllLines($file.FullName)
        $className = $null
        $baseName = "RefCounted"
        $isTool = $false
        $isAbstract = $false
        $limit = [Math]::Min($lines.Count, 40)
        for ($i = 0; $i -lt $limit; $i++) {
            $line = $lines[$i].Trim()
            if ($line -match '^@tool\b') { $isTool = $true }
            if ($line -match '^@abstract\b') { $isAbstract = $true }
            if ($line -match '^class_name\s+([A-Za-z_][A-Za-z0-9_]*)') {
                $className = $Matches[1]
            }
            if ($line -match '^extends\s+([A-Za-z_][A-Za-z0-9_]*)') {
                $baseName = $Matches[1]
            }
        }
        if ($className) {
            $relPath = $file.FullName.Substring($ProjectRoot.Length + 1).Replace('\', '/')
            $entries.Add([PSCustomObject]@{
                ClassName  = $className
                BaseName   = $baseName
                IsAbstract = if ($isAbstract) { "true" } else { "false" }
                IsTool     = if ($isTool) { "true" } else { "false" }
                ResPath    = "res://$relPath"
            })
        }
    }

    $sorted = $entries | Sort-Object -Property @{ Expression = { $_.ClassName }; Ascending = $true } -CaseSensitive
    $blocks = foreach ($item in $sorted) {
        "{" + "`n" +
        "`"base`": &`"$($item.BaseName)`"," + "`n" +
        "`"class`": &`"$($item.ClassName)`"," + "`n" +
        "`"icon`": `"`"," + "`n" +
        "`"is_abstract`": $($item.IsAbstract)," + "`n" +
        "`"is_tool`": $($item.IsTool)," + "`n" +
        "`"language`": &`"GDScript`"," + "`n" +
        "`"path`": `"$($item.ResPath)`"" + "`n" +
        "}"
    }
    $newContent = "list=[" + ($blocks -join ", ") + "]`n"
    $existingContent = if (Test-Path $cachePath) { [System.IO.File]::ReadAllText($cachePath).Replace("`r`n", "`n") } else { "" }
    if ($existingContent -ne $newContent) {
        [System.IO.File]::WriteAllText($cachePath, $newContent, [System.Text.UTF8Encoding]::new($false))
    }
}

# 1. Network facade convention: forbid deprecated App.network (use App.net)
$netMatches = Get-ChildItem -Path "$root\src" -Recurse -Include *.gd | Select-String -Pattern 'App\.network\b'
if ($netMatches) {
    Write-Host "[FAIL] Deprecated 'App.network' usage detected (use 'App.net'):" -ForegroundColor Red
    $netMatches | ForEach-Object { Write-Host "       - $($_.Path):$($_.LineNumber) -> $($_.Line.Trim())" -ForegroundColor Red }
    $errorCount += $netMatches.Count
} else {
    Write-Host "[PASS] Network facade convention (App.net)" -ForegroundColor Green
}

# 2. Singular domain path rule: forbid infra/params/ (use infra/param/)
$paramsMatches = Get-ChildItem -Path "$root\src", "$root\addons", "$root\docs" -Recurse -Include *.gd, *.md, *.tscn -ErrorAction SilentlyContinue | 
    Select-String -Pattern 'infra/params/' |
    Where-Object { -not ($_.Path -like "*.md" -and $_.Line.Trim().StartsWith("|")) }

if ($paramsMatches) {
    Write-Host "[FAIL] Deprecated plural path 'infra/params/' detected (use 'infra/param/'):" -ForegroundColor Red
    $paramsMatches | ForEach-Object { Write-Host "       - $($_.Path):$($_.LineNumber) -> $($_.Line.Trim())" -ForegroundColor Red }
    $errorCount += $paramsMatches.Count
} else {
    Write-Host "[PASS] Singular domain path (infra/param/)" -ForegroundColor Green
}

# 3. Plural asset container path rule: forbid assets/video/ (use assets/videos/)
$videoMatches = Get-ChildItem -Path "$root\src", "$root\addons", "$root\docs" -Recurse -Include *.gd, *.md, *.tscn -ErrorAction SilentlyContinue | 
    Select-String -Pattern 'assets/video/' |
    Where-Object { -not ($_.Path -like "*.md" -and $_.Line.Trim().StartsWith("|")) }

if ($videoMatches) {
    Write-Host "[FAIL] Deprecated singular path 'assets/video/' detected (use 'assets/videos/'):" -ForegroundColor Red
    $videoMatches | ForEach-Object { Write-Host "       - $($_.Path):$($_.LineNumber) -> $($_.Line.Trim())" -ForegroundColor Red }
    $errorCount += $videoMatches.Count
} else {
    Write-Host "[PASS] Plural asset container path (assets/videos/)" -ForegroundColor Green
}

# 4. Logger module path rule: forbid modules/log/ (use modules/logger/)
$loggerMatches = Get-ChildItem -Path "$root\src", "$root\addons", "$root\docs" -Recurse -Include *.gd, *.md, *.tscn -ErrorAction SilentlyContinue | Select-String -Pattern 'modules/log/'
if ($loggerMatches) {
    Write-Host "[FAIL] Deprecated module path 'modules/log/' detected (use 'modules/logger/'):" -ForegroundColor Red
    $loggerMatches | ForEach-Object { Write-Host "       - $($_.Path):$($_.LineNumber) -> $($_.Line.Trim())" -ForegroundColor Red }
    $errorCount += $loggerMatches.Count
} else {
    Write-Host "[PASS] Logger module path (modules/logger/)" -ForegroundColor Green
}

# 5. Display layer decoupling & shared 3-pillar directory architecture
$uiDialogMatches = Get-ChildItem -Path "$root\src\framework\modules\display" -Recurse -Include *dialog*.gd, *modal*.gd, *toast*.gd -ErrorAction SilentlyContinue
if ($uiDialogMatches) {
    Write-Host "[FAIL] Business dialog/toast scripts found in 'framework/modules/display' (move to 'src/game/shared/component/'):" -ForegroundColor Red
    $uiDialogMatches | ForEach-Object { Write-Host "       - $($_.FullName)" -ForegroundColor Red }
    $errorCount += $uiDialogMatches.Count
} else {
    Write-Host "[PASS] Display layer decoupling (dialogs isolated in shared/component/)" -ForegroundColor Green
}

$legacySharedMatches = Get-ChildItem -Path "$root\src", "$root\docs" -Recurse -Include *.gd, *.md, *.tscn -ErrorAction SilentlyContinue |
    Select-String -Pattern 'shared/(define|components|models|constants|events|msvp)/'
$sharedUpwardDepMatches = Get-ChildItem -Path "$root\src\game\shared" -Recurse -Include *.gd -ErrorAction SilentlyContinue |
    Select-String -Pattern 'res://src/game/(features|bootstrap)/' |
    Where-Object { -not $_.Line.Trim().StartsWith("#") -and -not ($_.Path -like "*\model\config\game_scenes.gd") }
if ($legacySharedMatches -or $sharedUpwardDepMatches) {
    if ($legacySharedMatches) {
        Write-Host "[FAIL] Legacy shared path reference detected (use 'shared/model|service|component/'):" -ForegroundColor Red
        $legacySharedMatches | ForEach-Object { Write-Host "       - $($_.Path):$($_.LineNumber) -> $($_.Line.Trim())" -ForegroundColor Red }
        $errorCount += $legacySharedMatches.Count
    }
    if ($sharedUpwardDepMatches) {
        Write-Host "[FAIL] Upward dependency from 'src/game/shared/' to 'features/' or 'bootstrap/' detected:" -ForegroundColor Red
        $sharedUpwardDepMatches | ForEach-Object { Write-Host "       - $($_.Path):$($_.LineNumber) -> $($_.Line.Trim())" -ForegroundColor Red }
        $errorCount += $sharedUpwardDepMatches.Count
    }
} else {
    Write-Host "[PASS] Shared 3-pillar architecture (model/service/component & zero upward deps)" -ForegroundColor Green
}

# 6. Unidirectional dependency boundary: src/framework/ must never reference src/game/ or src/test/
$reverseDepMatches = Get-ChildItem -Path "$root\src\framework" -Recurse -Include *.gd |
    Select-String -Pattern 'res://src/(game|test)/' |
    Where-Object { -not $_.Line.Trim().StartsWith("#") }
if ($reverseDepMatches) {
    Write-Host "[FAIL] Reverse dependency from 'src/framework/' to 'src/game/' or 'src/test/' detected:" -ForegroundColor Red
    $reverseDepMatches | ForEach-Object { Write-Host "       - $($_.Path):$($_.LineNumber) -> $($_.Line.Trim())" -ForegroundColor Red }
    $errorCount += $reverseDepMatches.Count
} else {
    Write-Host "[PASS] Unidirectional dependency boundary (zero game/test imports in framework)" -ForegroundColor Green
}

# 7. Explicit dependency injection: forbid implicit App.xxx calls inside modules/infra/util
$hiddenAppMatches = Get-ChildItem -Path "$root\src\framework\modules", "$root\src\framework\infra", "$root\src\framework\util" -Recurse -Include *.gd |
    Select-String -Pattern '\bApp\.' |
    Where-Object { -not $_.Line.Trim().StartsWith("#") }
if ($hiddenAppMatches) {
    Write-Host "[FAIL] Implicit 'App.xxx' access inside 'framework/modules|infra|util' (use constructor DI):" -ForegroundColor Red
    $hiddenAppMatches | ForEach-Object { Write-Host "       - $($_.Path):$($_.LineNumber) -> $($_.Line.Trim())" -ForegroundColor Red }
    $errorCount += $hiddenAppMatches.Count
} else {
    Write-Host "[PASS] Explicit dependency injection (zero implicit App.xxx in modules/infra/util)" -ForegroundColor Green
}

# 8. Core module dependency manifests (MODULE_ID / REQUIRED_MODULES / OPTIONAL_MODULES)
$moduleImplFiles = @(
    "env\impl\runtime_environment.gd",
    "logger\impl\framework_logger.gd",
    "clock\impl\clock_system.gd",
    "asset\impl\asset_system.gd",
    "input\impl\input_system.gd",
    "haptic\impl\haptic_feedback.gd",
    "network\impl\network_client.gd",
    "storage\impl\storage_system.gd",
    "locale\impl\localization_system.gd",
    "scene\impl\scene_router.gd",
    "display\impl\display_system.gd",
    "audio\impl\audio_system.gd",
    "video\impl\video_player.gd"
)
$missingManifestCount = 0
foreach ($relPath in $moduleImplFiles) {
    $fullPath = Join-Path "$root\src\framework\modules" $relPath
    if (-not (Test-Path $fullPath)) {
        Write-Host "[FAIL] Missing core module implementation file: $fullPath" -ForegroundColor Red
        $missingManifestCount++
        continue
    }
    $content = Get-Content -Path $fullPath -Raw
    if ($content -notmatch 'const\s+MODULE_ID\b' -or $content -notmatch 'const\s+REQUIRED_MODULES\b' -or $content -notmatch 'const\s+OPTIONAL_MODULES\b') {
        Write-Host "[FAIL] Incomplete dependency manifest (MODULE_ID / REQUIRED_MODULES / OPTIONAL_MODULES): $relPath" -ForegroundColor Red
        $missingManifestCount++
    }
}
if ($missingManifestCount -gt 0) {
    $errorCount += $missingManifestCount
} else {
    Write-Host "[PASS] Core module dependency manifests (13/13 modules verified)" -ForegroundColor Green
}

# 9. Facade boundary isolation: forbid referencing internal impl classes from src/game/
$internalClassesPattern = '\b(RuntimeManifest|RuntimeServiceHost|RuntimeEnvironment|FrameworkLogger|ClockSystem|AssetSystem|AssetCache|ResourceLoaderAdapter|StorageSystem|StorageCache|StorageMigrator|MemoryStorageDriver|DiskStorageDriver|RemoteStorageDriver|NetworkClient|RequestQueue|SceneRouter|SceneStack|SceneTransition|DisplaySystem|AudioSystem|BgmPlayer|SfxPool|LocalizationSystem|TranslationServerAdapter|HapticFeedback|InputSystem|InputDeviceTracker|InputRebindCapturer|InputMapAdapter|VideoPlayer)\b'
$implLeakMatches = Get-ChildItem -Path "$root\src\game" -Recurse -Include *.gd |
    Select-String -Pattern $internalClassesPattern |
    Where-Object { -not $_.Line.Trim().StartsWith("#") }
if ($implLeakMatches) {
    Write-Host "[FAIL] Direct reference to internal 'impl/' class in 'src/game/' (program against 'Base*' facades):" -ForegroundColor Red
    $implLeakMatches | ForEach-Object { Write-Host "       - $($_.Path):$($_.LineNumber) -> $($_.Line.Trim())" -ForegroundColor Red }
    $errorCount += $implLeakMatches.Count
} else {
    Write-Host "[PASS] Facade boundary isolation (zero internal impl leaks in src/game/)" -ForegroundColor Green
}

# 10. Codec, async & spine utilities consolidation
$deprecatedUtilsMatches = Get-ChildItem -Path "$root\src" -Recurse -Include *.gd |
    Select-String -Pattern '\b(FileCodecType|ImageFileCodec|Texture2DFileCodec|AsyncUtils|SpineUtils)\b|TimeUtils\.wait_safe' |
    Where-Object { -not $_.Line.Trim().StartsWith("#") }
if ($deprecatedUtilsMatches) {
    Write-Host "[FAIL] Deprecated utility usage detected (FileCodecType/ImageFileCodec/Texture2DFileCodec/AsyncUtils/SpineUtils/TimeUtils.wait_safe):" -ForegroundColor Red
    $deprecatedUtilsMatches | ForEach-Object { Write-Host "       - $($_.Path):$($_.LineNumber) -> $($_.Line.Trim())" -ForegroundColor Red }
    $errorCount += $deprecatedUtilsMatches.Count
} else {
    Write-Host "[PASS] Codec, async & spine consolidation (FileCodecUtils / ResourceCodecUtils / TaskScope / SpinePool)" -ForegroundColor Green
}

# 11. GDScript syntax & static type compilation (Godot Headless with Class Cache Sync & Timeout Protection)
Sync-GodotGlobalClassCache -ProjectRoot $root

$godotBin = $env:GODOT_BIN
if (-not $godotBin -or -not (Test-Path $godotBin)) {
    $cmd = Get-Command godot -ErrorAction SilentlyContinue
    if ($cmd) {
        $godotBin = $cmd.Source
    }
}
if (-not $godotBin -or -not (Test-Path $godotBin)) {
    # Prefer direct main executable over _console.exe wrapper to prevent orphaned child processes
    $candidates = @(
        "D:\software\Godot\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe",
        "D:\software\Godot\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe"
    )
    foreach ($cand in $candidates) {
        if (Test-Path $cand) {
            $godotBin = $cand
            break
        }
    }
}

if ($godotBin -and (Test-Path $godotBin)) {
    $syntaxScript = Join-Path $PSScriptRoot "check_syntax.gd"
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $godotBin
    $psi.Arguments = "--headless --quit --path `"$root`" -s `"$syntaxScript`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    [void]$proc.Start()
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()

    $exited = $proc.WaitForExit(15000)
    if (-not $exited) {
        try { $proc.Kill($true) } catch {}
        Write-Host "[FAIL] GDScript syntax check timed out after 15s (process terminated):" -ForegroundColor Red
        $errorCount++
    } else {
        $proc.WaitForExit()
        $combinedOutput = ($stdoutTask.GetAwaiter().GetResult() + "`n" + $stderrTask.GetAwaiter().GetResult()) -split "`r?`n"
        $syntaxExit = $proc.ExitCode
        $passLine = $combinedOutput | Where-Object { $_ -match '^\[SYNTAX_PASS\]\s+(\d+)' } | Select-Object -First 1
        $errLines = $combinedOutput | Where-Object { $_ -match 'SCRIPT ERROR:|Parse Error:|Compile Error:|\[SYNTAX_FAIL\]' }
        if ($syntaxExit -eq 0 -and $passLine -and -not $errLines) {
            $scriptCount = ($passLine -replace '^\[SYNTAX_PASS\]\s+', '').Trim()
            Write-Host "[PASS] GDScript syntax & static type compilation ($scriptCount scripts verified)" -ForegroundColor Green
        } else {
            Write-Host "[FAIL] GDScript syntax or static type compilation failed:" -ForegroundColor Red
            $combinedOutput | Where-Object {
                $_ -match 'SCRIPT ERROR:|Parse Error:|Compile Error:|\[SYNTAX_FAIL\]|\sat:\s'
            } | ForEach-Object {
                Write-Host "       $_" -ForegroundColor Red
            }
            $errorCount++
        }
    }
    $proc.Dispose()
} else {
    Write-Host "[WARN] Godot binary not found (set GODOT_BIN to enable full syntax compilation)" -ForegroundColor Yellow
    $warnCount++
}

# 12. Raw print() warning (prefer App.logger)
$printMatches = Get-ChildItem -Path "$root\src\framework", "$root\src\game" -Recurse -Include *.gd | Select-String -Pattern '^\s*print\('
if ($printMatches) {
    Write-Host "[WARN] Found $($printMatches.Count) raw print() call(s) (prefer App.logger)" -ForegroundColor Yellow
    $warnCount += $printMatches.Count
} else {
    Write-Host "[PASS] No raw print() statements found" -ForegroundColor Green
}

Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
if ($errorCount -eq 0) {
    Write-Host "[OK] All compliance & syntax checks passed ($errorCount errors, $warnCount warnings)" -ForegroundColor Green
    exit 0
} else {
    Write-Host "[ERROR] Compliance check failed ($errorCount errors, $warnCount warnings)" -ForegroundColor Red
    exit 1
}
