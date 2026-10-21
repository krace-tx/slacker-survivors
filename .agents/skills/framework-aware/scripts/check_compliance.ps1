# ==============================================================================
# Framework Compliance Checker (Slacker Survivors)
# ==============================================================================
# 该脚本用于自动化扫描工程代码与文档，确保符合项目框架规范与单复数黄金法则。
#
# 使用方式:
#   pwsh .agents/skills/framework-aware/scripts/check_compliance.ps1
# ==============================================================================

[CmdletBinding()]
param()

$root = (Get-Item $PSScriptRoot).Parent.Parent.Parent.Parent.FullName
Write-Host "🔍 [Framework-Aware] 开始扫描项目架构合规性: $root" -ForegroundColor Cyan

$errorCount = 0
$warnCount = 0

# 1. 检查已废弃的旧网络门面 App.network (应为 App.net)
$netMatches = Get-ChildItem -Path "$root\src" -Recurse -Include *.gd | Select-String -Pattern 'App\.network\b'
if ($netMatches) {
    Write-Host "❌ 发现非法调用已移除的 App.network 属性 (应改为 App.net):" -ForegroundColor Red
    $netMatches | ForEach-Object { Write-Host "   - $($_.Path):$($_.LineNumber) -> $($_.Line.Trim())" -ForegroundColor Red }
    $errorCount += $netMatches.Count
} else {
    Write-Host "✅ 网络门面调用合规 (统一使用 App.net)" -ForegroundColor Green
}

# 2. 检查单复数黄金法则违规路径: infra/params (应为 infra/param)
$paramsMatches = Get-ChildItem -Path "$root\src", "$root\addons", "$root\docs" -Recurse -Include *.gd, *.md, *.tscn | 
    Select-String -Pattern 'infra/params/' |
    Where-Object { -not ($_.Path -like "*.md" -and $_.Line.Trim().StartsWith("|")) }

if ($paramsMatches) {
    Write-Host "❌ 发现已废弃的复数路径 infra/params/ (技术域应为单数 infra/param/):" -ForegroundColor Red
    $paramsMatches | ForEach-Object { Write-Host "   - $($_.Path):$($_.LineNumber) -> $($_.Line.Trim())" -ForegroundColor Red }
    $errorCount += $paramsMatches.Count
} else {
    Write-Host "✅ 参数域路径合规 (统一使用 infra/param/)" -ForegroundColor Green
}

# 3. 检查单复数黄金法则违规路径: assets/video/ (应为 assets/videos/)
$videoMatches = Get-ChildItem -Path "$root\src", "$root\addons", "$root\docs" -Recurse -Include *.gd, *.md, *.tscn | 
    Select-String -Pattern 'assets/video/' |
    Where-Object { -not ($_.Path -like "*.md" -and $_.Line.Trim().StartsWith("|")) }

if ($videoMatches) {
    Write-Host "❌ 发现已废弃的单数资源路径 assets/video/ (资源容器应为复数 assets/videos/):" -ForegroundColor Red
    $videoMatches | ForEach-Object { Write-Host "   - $($_.Path):$($_.LineNumber) -> $($_.Line.Trim())" -ForegroundColor Red }
    $errorCount += $videoMatches.Count
} else {
    Write-Host "✅ 视频资源路径合规 (统一使用 assets/videos/)" -ForegroundColor Green
}

# 4. 检查模块路径违规: modules/log/ (已重命名为 modules/logger/)
$loggerMatches = Get-ChildItem -Path "$root\src", "$root\addons", "$root\docs" -Recurse -Include *.gd, *.md, *.tscn | Select-String -Pattern 'modules/log/'
if ($loggerMatches) {
    Write-Host "❌ 发现已废弃的模块路径 modules/log/ (应为 modules/logger/):" -ForegroundColor Red
    $loggerMatches | ForEach-Object { Write-Host "   - $($_.Path):$($_.LineNumber) -> $($_.Line.Trim())" -ForegroundColor Red }
    $errorCount += $loggerMatches.Count
} else {
    Write-Host "✅ 日志系统路径合规 (统一使用 modules/logger/)" -ForegroundColor Green
}

# 5. 检查业务弹窗是否误放在 framework 层，以及是否存在已移除的冗余路径 shared/components/ui/ 或 shared/msvp/
$uiDialogMatches = Get-ChildItem -Path "$root\src\framework\modules\ui" -Recurse -Include *dialog*.gd, *modal*.gd, *toast*.gd -ErrorAction SilentlyContinue
if ($uiDialogMatches) {
    Write-Host "❌ 发现 framework/modules/ui 层残留业务弹窗组件 (应收敛至 src/game/shared/components/):" -ForegroundColor Red
    $uiDialogMatches | ForEach-Object { Write-Host "   - $($_.FullName)" -ForegroundColor Red }
    $errorCount += $uiDialogMatches.Count
} else {
    Write-Host "✅ UI 表现层职责解耦完全 (弹窗完全收敛在 shared/components/)" -ForegroundColor Green
}

$legacySharedMatches = Get-ChildItem -Path "$root\src", "$root\docs" -Recurse -Include *.gd, *.md, *.tscn |
    Select-String -Pattern 'shared/components/ui/|shared/msvp/'
if ($legacySharedMatches) {
    Write-Host "❌ 发现已移除的旧版路径引用 (shared/components/ui/ 或 shared/msvp/):" -ForegroundColor Red
    $legacySharedMatches | ForEach-Object { Write-Host "   - $($_.Path):$($_.LineNumber) -> $($_.Line.Trim())" -ForegroundColor Red }
    $errorCount += $legacySharedMatches.Count
} else {
    Write-Host "✅ Shared 目录引用合规 (已扁平化至 shared/components/ 且移除空壳 msvp 基类)" -ForegroundColor Green
}

# 6. 警告项：检查源码中残留的原生 print 语句 (应优先使用 App.logger)
$printMatches = Get-ChildItem -Path "$root\src\framework", "$root\src\game" -Recurse -Include *.gd | Select-String -Pattern '^\s*print\('
if ($printMatches) {
    Write-Host "⚠️ 提示: 发现 $($printMatches.Count) 处原生 print() 调用，建议迁移至 App.logger:" -ForegroundColor Yellow
    $warnCount += $printMatches.Count
} else {
    Write-Host "✅ 无原生裸 print 调用" -ForegroundColor Green
}

Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
if ($errorCount -eq 0) {
    Write-Host "🎉 恭喜！项目架构合规性扫描全部通过！(警告: $warnCount 处)" -ForegroundColor Green
    exit 0
} else {
    Write-Host "🚫 存在 $errorCount 处硬性合规错误，请修复后再提交！" -ForegroundColor Red
    exit 1
}
