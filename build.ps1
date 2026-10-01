<#
ClassName: build.ps1
Author:    Claude
Date:      2026-10-01
Description: TvRemoteController 构建脚本，编译 app / server 模块的 Debug APK
             用法: .\build.ps1 [-Module app|server|all] [-Clean]
#>
[CmdletBinding()]
param(
    [ValidateSet('app', 'server', 'all')]
    [string]$Module = 'all',

    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

# ---------- 环境检查 ----------
# 本项目为 Gradle 6.5 + AGP 4.1.0，只支持 JDK 8 ~ 14
$javaExe = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME 'bin\java.exe' } else { $null }
if ($javaExe -and (Test-Path $javaExe)) {
    # java -version 输出到 stderr，需临时放开 ErrorActionPreference 以免被当成终止错误
    $ErrorActionPreference = 'Continue'
    try {
        $verOut = & $javaExe -version 2>&1 | Out-String
    } finally {
        $ErrorActionPreference = 'Stop'
    }
    if ($verOut -match 'version "(\d+)') {
        $major = [int]$Matches[1]
        if ($major -gt 14) {
            Write-Host ''
            Write-Host "  [错误] JAVA_HOME 指向 JDK $major，本项目 Gradle 6.5 / AGP 4.1.0 仅支持 JDK 8 ~ 14。" -ForegroundColor Red
            Write-Host "         构建将失败。请安装 JDK 8 后重新设置 JAVA_HOME，例如：" -ForegroundColor Red
            Write-Host '         $env:JAVA_HOME = "C:\Program Files\Java\jdk1.8.0_xxx"' -ForegroundColor Yellow
            Write-Host ''
        }
    }
} else {
    Write-Warning 'JAVA_HOME 未设置或无效，将使用 PATH 中的 java。'
}

# ---------- 组装 Gradle 任务 ----------
$apkMap = @{
    app    = 'app\build\outputs\apk\debug\app-debug.apk'
    server = 'server\build\outputs\apk\debug\server-debug.apk'
}

$targets = if ($Module -eq 'all') { @('app', 'server') } else { @($Module) }

$tasks = @()
if ($Clean) { $tasks += 'clean' }
$tasks += $targets | ForEach-Object { ":$($_)`:assembleDebug" }

# ---------- 执行构建 ----------
Write-Host ("执行: gradlew.bat " + ($tasks -join ' ')) -ForegroundColor Cyan
& "$PSScriptRoot\gradlew.bat" @tasks --console=plain

if ($LASTEXITCODE -ne 0) {
    Write-Host ''
    Write-Host '构建失败，常见原因:' -ForegroundColor Red
    Write-Host '  1) JDK 版本过高 —— 若报 "Unsupported class file major version 6x"，请改用 JDK 8。'
    Write-Host '  2) 依赖拉不到 —— jcenter() 已停服，且 com.scwang.smart 等依赖不在 mavenCentral。'
    Write-Host '     解决: 把根 build.gradle 中 buildscript 与 allprojects 两处的 jcenter() 改为:'
    Write-Host '           maven { url "https://maven.aliyun.com/repository/public" }'
    exit $LASTEXITCODE
}

# ---------- 输出产物 ----------
Write-Host ''
Write-Host '构建完成，产物如下:' -ForegroundColor Green
foreach ($m in $targets) {
    $apk = Join-Path $PSScriptRoot $apkMap[$m]
    if (Test-Path $apk) {
        $size = [math]::Round((Get-Item $apk).Length / 1MB, 2)
        Write-Host ("  [{0}] {1}  ({2} MB)" -f $m, $apk, $size)
    } else {
        Write-Host ("  [{0}] 未找到 APK: {1}" -f $m, $apk) -ForegroundColor Yellow
    }
}
