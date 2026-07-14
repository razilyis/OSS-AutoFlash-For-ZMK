# AutoFlash for ZMK (Windows) を自己完結・単一 exe にパブリッシュし、配布用 zip を作る。
# 必要環境: .NET 8 SDK 以降
#Requires -Version 7
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$project = Join-Path $root 'windows\AutoFlash\AutoFlash.csproj'
$outDir = Join-Path $root 'dist\windows'

# WPF はトリミング(PublishTrimmed)非対応のため使わない
dotnet publish $project -c Release -r win-x64 --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:EnableCompressionInSingleFile=true `
    -o $outDir
if ($LASTEXITCODE -ne 0) { throw 'dotnet publish failed' }

$version = (Select-Xml -Path $project -XPath '//Version').Node.InnerText.Trim()
$zip = Join-Path $root "dist\AutoFlashForZMK-win-x64-$version.zip"
Remove-Item $zip -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $outDir 'AutoFlash.exe') -DestinationPath $zip

Write-Host "Built: $zip"
Write-Host "実行: $outDir\AutoFlash.exe"
