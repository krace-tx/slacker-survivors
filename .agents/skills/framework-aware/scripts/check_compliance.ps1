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

# 5. Display & Video layer UI decoupling & shared 3-pillar directory architecture
$uiDialogMatches = Get-ChildItem -Path "$root\src\framework\modules\display", "$root\src\framework\modules\video" -Recurse -Include *dialog*.gd, *modal*.gd, *toast*.gd, *overlay*.gd -ErrorAction SilentlyContinue
if ($uiDialogMatches) {
    Write-Host "[FAIL] Business UI dialog/toast/overlay scripts found in 'framework/modules/display|video' (keep framework UI-agnostic):" -ForegroundColor Red
    $uiDialogMatches | ForEach-Object { Write-Host "       - $($_.FullName)" -ForegroundColor Red }
    $errorCount += $uiDialogMatches.Count
} else {
    Write-Host "[PASS] Display & Video layer decoupling (zero hardcoded UI overlays/dialogs in framework)" -ForegroundColor Green
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
$internalClassesPattern = '\b(RuntimeManifest|RuntimeServiceHost|RuntimeEnvironment|FrameworkLogger|ClockSystem|AssetSystem|AssetCache|ResourceLoaderAdapter|StorageSystem|StorageCache|StorageMigrator|MemoryStorageDriver|DiskStorageDriver|RemoteStorageDriver|NetworkClient|RequestQueue|SceneRouter|SceneStack|SceneTransition|DisplaySystem|AudioSystem|BgmPlayer|SfxPool|LocalizationSystem|TranslationServerAdapter|HapticFeedback|InputSystem|InputDeviceTracker|InputRebindCapturer|InputMapAdapter|VideoPlayer|VideoStreamHost|VideoPrewarmer|VideoCacheManager)\b'
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

# 13. Asset topology, naming & dependency boundary (see src/assets/_doc_assets.md)
$assetRoot = Join-Path $root "src\assets"
$assetFails = [System.Collections.Generic.List[string]]::new()
$assetWarns = [System.Collections.Generic.List[string]]::new()
$assetFileCount = 0
# container key -> allowed extensions / allowed prefixes
$assetContainers = @{
    "textures"  = @{ Ext = @("png", "svg", "webp", "jpg", "jpeg", "exr", "hdr", "tres"); Prefix = @("tex", "spr", "sht", "atl", "ui", "btn", "ico", "fx") }
    "spines"    = @{ Ext = @("skel", "spine-json", "atlas", "png", "tres"); Prefix = @("spn") }
    "models"    = @{ Ext = @("glb", "gltf", "bin"); Prefix = @("mdl", "skm") }
    "materials" = @{ Ext = @("tres"); Prefix = @("mat", "ptc") }
    "shaders"   = @{ Ext = @("gdshader", "gdshaderinc"); Prefix = @("shd") }
    "themes"    = @{ Ext = @("tres"); Prefix = @("thm", "sbx") }
    "fonts"     = @{ Ext = @("ttf", "otf", "woff", "woff2", "tres"); Prefix = @("fnt") }
    "audio/bgm" = @{ Ext = @("ogg", "mp3"); Prefix = @("bgm") }
    "audio/sfx" = @{ Ext = @("wav", "ogg"); Prefix = @("sfx") }
    "audio/vox" = @{ Ext = @("ogg", "mp3"); Prefix = @("vox") }
    "audio/amb" = @{ Ext = @("ogg"); Prefix = @("amb") }
    "videos"    = @{ Ext = @("ogv", "mp4", "webm"); Prefix = @("vid") }
}
$assetForbiddenTokens = @("final", "new", "old", "copy", "tmp", "temp", "bak", "backup", "test")
$featureRoot = Join-Path $root "src\game\features"
$knownDomains = @{}

if (Test-Path $assetRoot) {
    foreach ($file in (Get-ChildItem -Path $assetRoot -Recurse -File -Force)) {
        $name = $file.Name
        if ($name -like "*.import" -or $name -like "*.uid" -or $name -eq ".gitkeep" -or $name -eq ".gdignore" -or $name -like "_doc_*.md") {
            continue
        }
        $assetFileCount++
        $rel = $file.FullName.Substring($assetRoot.Length + 1).Replace('\', '/')
        $parts = $rel.Split('/')
        $container = $parts[0]
        $offset = 1
        if ($container -eq "audio" -and $parts.Count -ge 2) {
            $container = "audio/" + $parts[1]
            $offset = 2
        }
        if (-not $assetContainers.ContainsKey($container)) {
            $assetFails.Add("Unknown media container '$container' -> $rel")
            continue
        }
        $depth = $parts.Count - $offset   # domain + [group] + file
        if ($depth -lt 2 -or $depth -gt 3) {
            $assetFails.Add("Invalid depth (expect <container>/<domain>/[<group>/]<file>) -> $rel")
            continue
        }
        $domain = $parts[$offset]
        $knownDomains[$domain] = $true
        $dotIdx = $name.IndexOf('.')
        if ($dotIdx -le 0) {
            $assetFails.Add("Missing extension -> $rel")
            continue
        }
        $stem = $name.Substring(0, $dotIdx)
        $ext = $name.Substring($dotIdx + 1)
        $spec = $assetContainers[$container]
        if ($spec.Ext -notcontains $ext) {
            $assetFails.Add("Extension '.$ext' not allowed in '$container/' (DCC sources belong in art/) -> $rel")
            continue
        }
        if ($stem -cnotmatch '^[a-z][a-z0-9]*(_[a-z0-9]+)*$' -or $stem.Length -gt 64) {
            $assetFails.Add("Stem must be lowercase snake_case <= 64 chars -> $rel")
            continue
        }
        $tokens = $stem.Split('_')
        $badToken = $tokens | Where-Object { ($assetForbiddenTokens -contains $_) -or ($_ -match '^v\d+$') -or ($_ -match '^\d$') } | Select-Object -First 1
        if ($badToken) {
            $assetFails.Add("Forbidden/invalid token '$badToken' (no version words, numbers need >= 2 digits) -> $rel")
            continue
        }
        if ($spec.Prefix -notcontains $tokens[0]) {
            $assetFails.Add("Prefix '$($tokens[0])_' not allowed in '$container/' (allowed: $($spec.Prefix -join ', ')) -> $rel")
            continue
        }
        $expectedHead = "$($tokens[0])_$($domain)_"
        if (-not $stem.StartsWith($expectedHead) -or $stem.Length -le $expectedHead.Length) {
            $assetFails.Add("Name must be '<prefix>_$($domain)_<subject>...' (domain token == folder) -> $rel")
            continue
        }
    }
    foreach ($d in $knownDomains.Keys) {
        if ($d -ne "shared" -and -not (Test-Path (Join-Path $featureRoot $d))) {
            $assetWarns.Add("Asset domain '$d' has no matching src/game/features/$d/")
        }
    }
}

# 13b. Framework must never reference business assets
$fwAssetRefs = Get-ChildItem -Path "$root\src\framework" -Recurse -Include *.gd, *.tscn, *.tres -ErrorAction SilentlyContinue |
    Select-String -Pattern 'res://src/assets/' |
    Where-Object { -not $_.Line.Trim().StartsWith("#") }
foreach ($m in $fwAssetRefs) {
    $assetFails.Add("Framework references business asset -> $($m.Path):$($m.LineNumber)")
}

# 13c. Game layer asset ownership: features/<f> -> {<f>, shared}; shared & bootstrap -> {shared}
$gameRoot = Join-Path $root "src\game"
$gameAssetRefs = Get-ChildItem -Path $gameRoot -Recurse -Include *.gd, *.tscn, *.tres -ErrorAction SilentlyContinue |
    Select-String -Pattern 'res://src/assets/([A-Za-z0-9_\-./]+)' -AllMatches |
    Where-Object { -not $_.Line.Trim().StartsWith("#") }
foreach ($m in $gameAssetRefs) {
    $relCode = $m.Path.Substring($gameRoot.Length + 1).Replace('\', '/')
    $codeParts = $relCode.Split('/')
    $allowed = @("shared")
    if ($codeParts[0] -eq "features" -and $codeParts.Count -ge 2) {
        $allowed += $codeParts[1]
    }
    foreach ($match in $m.Matches) {
        $assetParts = $match.Groups[1].Value.Split('/')
        $domIdx = if ($assetParts[0] -eq "audio") { 2 } else { 1 }
        $dom = if ($assetParts.Count -gt $domIdx + 1) { $assetParts[$domIdx] } else { "<none>" }
        if ($allowed -notcontains $dom) {
            $assetFails.Add("Cross-domain asset reference (domain '$dom' not in [$($allowed -join ', ')]) -> $($m.Path):$($m.LineNumber)")
        }
    }
}

if ($assetFails.Count -gt 0) {
    Write-Host "[FAIL] Asset topology / naming / ownership violations (see src/assets/_doc_assets.md):" -ForegroundColor Red
    $assetFails | ForEach-Object { Write-Host "       - $_" -ForegroundColor Red }
    $errorCount += $assetFails.Count
} else {
    Write-Host "[PASS] Asset topology, naming & ownership ($assetFileCount assets verified)" -ForegroundColor Green
}
if ($assetWarns.Count -gt 0) {
    $assetWarns | ForEach-Object { Write-Host "[WARN] $_" -ForegroundColor Yellow }
    $warnCount += $assetWarns.Count
}

# 14. Global class reference: forbid redundant preload/load aliases of scripts that already declare class_name
$srcRoot = Join-Path $root "src"
$globalClassPaths = @{}
foreach ($gd in (Get-ChildItem -Path $srcRoot -Recurse -Filter *.gd -File -ErrorAction SilentlyContinue)) {
    $cnLine = Select-String -Path $gd.FullName -Pattern '^class_name\s+(\w+)' | Select-Object -First 1
    if ($cnLine) {
        $resPath = "res://" + $gd.FullName.Substring($root.Length + 1).Replace('\', '/')
        $globalClassPaths[$resPath] = $cnLine.Matches[0].Groups[1].Value
    }
}
$aliasFails = [System.Collections.Generic.List[string]]::new()
$scriptLoadRefs = Get-ChildItem -Path $srcRoot -Recurse -Include *.gd -ErrorAction SilentlyContinue |
    Select-String -Pattern '\b(pre)?load\(\s*"(res://src/[^"]+\.gd)"\s*\)' -AllMatches |
    Where-Object { -not $_.Line.Trim().StartsWith("#") }
foreach ($m in $scriptLoadRefs) {
    foreach ($match in $m.Matches) {
        $target = $match.Groups[2].Value
        if ($globalClassPaths.ContainsKey($target)) {
            $aliasFails.Add("$($m.Path):$($m.LineNumber) -> use global '$($globalClassPaths[$target])' instead of loading '$target'")
        }
    }
}
if ($aliasFails.Count -gt 0) {
    Write-Host "[FAIL] Redundant script preload/load alias of a global class_name (reference the class directly):" -ForegroundColor Red
    $aliasFails | ForEach-Object { Write-Host "       - $_" -ForegroundColor Red }
    $errorCount += $aliasFails.Count
} else {
    Write-Host "[PASS] Global class reference (zero redundant preload aliases of class_name scripts)" -ForegroundColor Green
}

# 15. Sandbox persistence topology & Tier-2 domain ownership (user:// & StorageItem)
$sandboxFails = [System.Collections.Generic.List[string]]::new()
# 15a. Forbid raw "user://" literals in src/game/
$gameUserRefs = Get-ChildItem -Path $gameRoot -Recurse -Include *.gd, *.tscn, *.tres -ErrorAction SilentlyContinue |
    Select-String -Pattern '"user://' |
    Where-Object { -not $_.Line.Trim().StartsWith("#") }
foreach ($m in $gameUserRefs) {
    $sandboxFails.Add("Raw 'user://' literal in game layer (use StorageItem.for_config / for_save) -> $($m.Path):$($m.LineNumber)")
}

# 15b. Forbid StorageItem construction outside model/ (*_model.gd) & enforce STORAGE_DOMAIN 1:1 mirror in src/game/
$gameGdFiles = Get-ChildItem -Path $gameRoot -Recurse -Filter *.gd -File -ErrorAction SilentlyContinue
foreach ($gd in $gameGdFiles) {
    $rel = $gd.FullName.Substring($gameRoot.Length + 1).Replace('\', '/')
    $parts = $rel.Split('/')
    $isModelFile = ($rel -match '(^|/)model/(.+/)?[a-z0-9_]+_model\.gd$')
    $storageConstruct = Select-String -Path $gd.FullName -Pattern 'StorageItem\.(new|for_config|for_save)\s*\(' |
        Where-Object { -not $_.Line.Trim().StartsWith("#") }
    if ($storageConstruct -and -not $isModelFile) {
        foreach ($sc in $storageConstruct) {
            $sandboxFails.Add("StorageItem constructed outside *_model.gd -> $($gd.FullName):$($sc.LineNumber)")
        }
    }
    $domainDecl = Select-String -Path $gd.FullName -Pattern 'const\s+STORAGE_DOMAIN\s*(:\s*StringName)?\s*=\s*&"([^"]+)"' |
        Where-Object { -not $_.Line.Trim().StartsWith("#") } | Select-Object -First 1
    if ($domainDecl) {
        $declaredDomain = $domainDecl.Matches[0].Groups[2].Value
        $expectedDomain = if ($parts[0] -eq "shared") { "shared" } elseif ($parts[0] -eq "features" -and $parts.Count -ge 2) { $parts[1] } else { "" }
        if ($expectedDomain -ne "" -and $declaredDomain -ne $expectedDomain) {
            $sandboxFails.Add("Tier-2 STORAGE_DOMAIN mismatch (expected '&`"$expectedDomain`"', got '&`"$declaredDomain`"') -> $($gd.FullName):$($domainDecl.LineNumber)")
        }
    }
}
if ($sandboxFails.Count -gt 0) {
    Write-Host "[FAIL] Sandbox persistence topology & Tier-2 domain violations:" -ForegroundColor Red
    $sandboxFails | ForEach-Object { Write-Host "       - $_" -ForegroundColor Red }
    $errorCount += $sandboxFails.Count
} else {
    Write-Host "[PASS] Sandbox persistence topology & Tier-2 domain ownership (user:// & StorageItem)" -ForegroundColor Green
}

Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
if ($errorCount -eq 0) {
    Write-Host "[OK] All compliance & syntax checks passed ($errorCount errors, $warnCount warnings)" -ForegroundColor Green
    exit 0
} else {
    Write-Host "[ERROR] Compliance check failed ($errorCount errors, $warnCount warnings)" -ForegroundColor Red
    exit 1
}
